-- Full-file diff tab. Two modes:
--   split:  old version left (read-only), new version right
--   inline: new version only; removed lines shown as red virtual lines, added lines green
local api = vim.api
local git = require('nice-git.git')

local M = {}

local ns = api.nvim_create_namespace('nice-git-inline')
local group = api.nvim_create_augroup('NiceGitDiff', {})

-- The open diff: { tab, root, row, mode, lspec, rspec, base, lbuf, rbuf, lwin, rwin }.
-- `base` holds the old version's lines; the new version always lives in `rbuf`.
local cur

-- Which version each pane shows. A string is a git object spec, `true` the working-tree file,
-- nil an empty pane (new or deleted file).
local function specs(section, e)
  if section == 'staged' then
    return 'HEAD:' .. (e.orig or e.path), ':' .. e.path
  elseif section == 'untracked' then
    return nil, true
  end
  return ':' .. e.path, e.status ~= 'D' or nil
end

local function label(spec, deleted)
  if spec == true then
    return 'Working Tree'
  elseif spec == nil then
    return deleted and '(deleted)' or '(new file)'
  end
  return spec:sub(1, 1) == ':' and 'Index' or 'HEAD'
end

local function load(root, spec, cb)
  if type(spec) == 'string' then
    git.show(root, spec, cb)
  else
    cb({})
  end
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

local function scratch(name, path, lines)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(b) == name then
      set_lines(b, lines)
      return b
    end
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, name)
  vim.bo[buf].bufhidden = 'wipe'
  set_lines(buf, lines)
  local ft = vim.filetype.match({ filename = path })
  if ft then
    vim.bo[buf].filetype = ft
  end
  return buf
end

local function join(lines)
  return #lines == 0 and '' or table.concat(lines, '\n') .. '\n'
end

---Hunks between the old version and the current contents of the new pane, as
---{ old_start, old_count, new_start, new_count } (1-based; a start is the line before when count is 0).
function M.hunks()
  if not (cur and api.nvim_buf_is_valid(cur.rbuf)) then
    return {}
  end
  local new = api.nvim_buf_get_lines(cur.rbuf, 0, -1, false)
  return vim.text.diff(join(cur.base), join(new), { result_type = 'indices' })
end

local function decorate()
  if not (cur and cur.mode == 'inline' and api.nvim_buf_is_valid(cur.rbuf)) then
    return
  end
  local buf = cur.rbuf
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local width = api.nvim_win_is_valid(cur.rwin) and api.nvim_win_get_width(cur.rwin) or 200
  local last = api.nvim_buf_line_count(buf)
  for _, h in ipairs(M.hunks()) do
    local sa, ca, sb, cb = unpack(h)
    if ca > 0 then
      local virt = {}
      for i = sa, sa + ca - 1 do
        local text = cur.base[i]:gsub('\t', (' '):rep(vim.bo[buf].tabstop))
        table.insert(virt, { { text .. (' '):rep(math.max(width - api.nvim_strwidth(text), 0)), 'NiceGitInlineDelete' } })
      end
      -- Removed lines go above the hunk's first new line, or below the line they followed.
      local above = cb > 0 or sb == 0
      local line = math.min(math.max(sb - 1, 0), last - 1)
      api.nvim_buf_set_extmark(buf, ns, line, 0, { virt_lines = virt, virt_lines_above = above })
    end
    for l = sb, sb + cb - 1 do
      api.nvim_buf_set_extmark(buf, ns, l - 1, 0, { line_hl_group = 'NiceGitInlineAdd' })
    end
  end
end

-- Toolbar buttons call back through this global; winbar click handlers can't hold closures.
local actions = {}
_G.NiceGitDiffClick = function(id)
  if actions[id] then
    vim.schedule(actions[id])
  end
end

local function button(id, text)
  return ('%%%d@v:lua.NiceGitDiffClick@%%#NiceGitToolbarButton# %s %%*%%X '):format(id, text)
end

local function title(path, spec, deleted)
  return '%#NiceGitToolbarTitle# ' .. path:gsub('%%', '%%%%') .. ' %#NiceGitToolbar#· ' .. label(spec, deleted) .. ' %*'
end

local function set_toolbars()
  local path = cur.row.entry.path
  local deleted = cur.row.entry.status == 'D'
  local bar = button(1, cur.mode == 'split' and '≡ Inline' or '⇆ Side by side')
    .. button(2, '↑')
    .. button(3, '↓')
  if cur.lwin then
    vim.wo[cur.lwin].winbar = title(path, cur.lspec, deleted)
    vim.wo[cur.rwin].winbar = title(path, cur.rspec, deleted) .. '%=' .. bar
  else
    vim.wo[cur.rwin].winbar = title(path, cur.lspec, deleted) .. ' → ' .. label(cur.rspec, deleted) .. '%=' .. bar
  end
end

---Moves the cursor to the next (dir > 0) or previous hunk, wrapping around.
function M.jump(dir)
  if not cur then
    return
  end
  local win = api.nvim_get_current_win()
  local old = win == cur.lwin
  if not old and win ~= cur.rwin then
    win = cur.rwin
  end
  local starts = {}
  for _, h in ipairs(M.hunks()) do
    table.insert(starts, math.max(old and h[1] or h[3], 1))
  end
  if #starts == 0 then
    return
  end
  local line = api.nvim_win_get_cursor(win)[1]
  local target = dir > 0 and starts[1] or starts[#starts]
  for i = 1, #starts do
    local s = dir > 0 and starts[i] or starts[#starts + 1 - i]
    if (dir > 0 and s > line) or (dir < 0 and s < line) then
      target = s
      break
    end
  end
  api.nvim_set_current_win(win)
  api.nvim_win_set_cursor(win, { math.min(target, api.nvim_buf_line_count(api.nvim_win_get_buf(win))), 0 })
  vim.cmd('normal! zz')
end

local KEYS = {
  [']c'] = function()
    M.jump(1)
  end,
  ['[c'] = function()
    M.jump(-1)
  end,
}

-- Undo everything the view added to buffers that outlive it (the working file in particular).
local function teardown()
  if not cur then
    return
  end
  -- The new-side buffer/window come first: the old side is nil in inline mode and ipairs stops there.
  api.nvim_clear_autocmds({ group = group })
  for _, buf in ipairs({ cur.rbuf, cur.lbuf }) do
    if buf and api.nvim_buf_is_valid(buf) then
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      for lhs in pairs(KEYS) do
        pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
      end
    end
  end
  for _, win in ipairs({ cur.rwin, cur.lwin }) do
    if win and api.nvim_win_is_valid(win) then
      vim.wo[win].winbar = ''
    end
  end
  cur = nil
end

local function show(view)
  teardown()
  local sidebar = require('nice-git.sidebar')
  local tab = view.tab
  if tab and api.nvim_tabpage_is_valid(tab) then
    api.nvim_set_current_tabpage(tab)
  else
    vim.cmd('tabnew')
  end
  vim.cmd('diffoff!')

  -- Reduce the tab to one editor window, then rebuild: [panel | left | right] or [panel | file].
  local panel = { [sidebar.buf] = true, [require('nice-git.commit').buf or -1] = true }
  local main
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if not panel[api.nvim_win_get_buf(w)] and api.nvim_win_get_config(w).relative == '' then
      main = w
      break
    end
  end
  if main then
    api.nvim_set_current_win(main)
  else
    vim.cmd('vnew')
    main = api.nvim_get_current_win()
  end
  vim.cmd('silent! only')

  local path = view.row.entry.path
  local rbuf
  if view.rspec == true then
    -- bufadd reuses an open (possibly modified) buffer where :edit would refuse.
    rbuf = vim.fn.bufadd(view.root .. '/' .. path)
    vim.fn.bufload(rbuf)
    vim.bo[rbuf].buflisted = true
    api.nvim_win_set_buf(main, rbuf)
  else
    rbuf = scratch('nice-git://' .. (view.rspec or 'deleted:' .. path), path, view.rlines)
    api.nvim_win_set_buf(main, rbuf)
  end

  local mode = require('nice-git').config.diff_mode
  local lbuf, lwin
  if mode == 'split' then
    lbuf = scratch('nice-git://' .. (view.lspec or 'new:' .. path), path, view.llines)
    vim.cmd('leftabove vsplit')
    lwin = api.nvim_get_current_win()
    api.nvim_win_set_buf(lwin, lbuf)
    for _, w in ipairs({ lwin, main }) do
      api.nvim_win_call(w, function()
        vim.cmd('diffthis')
      end)
      vim.wo[w].foldenable = false -- show the whole file, not just the hunks
    end
  end
  sidebar.open_win()

  cur = {
    tab = api.nvim_get_current_tabpage(),
    root = view.root,
    row = view.row,
    mode = mode,
    lspec = view.lspec,
    rspec = view.rspec,
    base = view.llines,
    lbuf = lbuf,
    rbuf = rbuf,
    lwin = lwin,
    rwin = main,
  }
  for _, buf in ipairs({ rbuf, lbuf }) do
    for lhs, fn in pairs(KEYS) do
      vim.keymap.set('n', lhs, fn, { buffer = buf, desc = 'nice-git: jump to hunk' })
    end
  end
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, { group = group, buffer = rbuf, callback = decorate })
  api.nvim_create_autocmd('TabClosed', {
    group = group,
    callback = function()
      if cur and not api.nvim_tabpage_is_valid(cur.tab) then
        teardown()
      end
    end,
  })
  set_toolbars()
  decorate()
  api.nvim_set_current_win(main)
  api.nvim_win_set_cursor(main, { 1, 0 })
  M.jump(1)
end

function M.open(state, row)
  local lspec, rspec = specs(row.section, row.entry)
  local tab = cur and cur.tab
  load(state.root, lspec, function(llines)
    load(state.root, rspec, function(rlines)
      show({ tab = tab, root = state.root, row = row, lspec = lspec, rspec = rspec, llines = llines, rlines = rlines })
    end)
  end)
end

function M.toggle_mode()
  local config = require('nice-git').config
  config.diff_mode = config.diff_mode == 'split' and 'inline' or 'split'
  if cur then
    M.open(require('nice-git').state, cur.row)
  end
end

actions[1] = M.toggle_mode
actions[2] = function()
  M.jump(-1)
end
actions[3] = function()
  M.jump(1)
end

---Re-reads the git-backed versions (e.g. after staging changed the index).
function M.refresh()
  if not (cur and api.nvim_tabpage_is_valid(cur.tab)) then
    return
  end
  local view = cur
  load(view.root, view.lspec, function(llines)
    if cur ~= view then
      return
    end
    view.base = llines
    if view.lbuf and api.nvim_buf_is_valid(view.lbuf) then
      set_lines(view.lbuf, llines)
    end
    local function done()
      if view.lwin and api.nvim_win_is_valid(view.lwin) then
        api.nvim_win_call(view.lwin, function()
          vim.cmd('diffupdate')
        end)
      end
      decorate()
    end
    if type(view.rspec) ~= 'string' then
      return done()
    end
    git.show(view.root, view.rspec, function(rlines)
      if cur == view and api.nvim_buf_is_valid(view.rbuf) then
        set_lines(view.rbuf, rlines)
        done()
      end
    end)
  end)
end

return M
