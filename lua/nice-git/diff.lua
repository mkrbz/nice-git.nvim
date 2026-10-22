-- Full-file side-by-side diff in a dedicated tab: old version left (read-only), new version right.
local api = vim.api
local git = require('nice-git.git')

local M = {}

local cur -- { tab, root, left = { buf, spec }, right = { buf, spec } }

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

local function show(state, path, lspec, rspec, llines, rlines)
  local sidebar = require('nice-git.sidebar')
  if cur and api.nvim_tabpage_is_valid(cur.tab) then
    api.nvim_set_current_tabpage(cur.tab)
  else
    vim.cmd('tabnew')
  end
  vim.cmd('diffoff!')

  -- Reduce the tab to one editor window, then rebuild: [sidebar | left | right].
  local main
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(w) ~= sidebar.buf and api.nvim_win_get_config(w).relative == '' then
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

  local rbuf
  if rspec == true then
    vim.cmd.edit(vim.fn.fnameescape(state.root .. '/' .. path))
    rbuf = api.nvim_get_current_buf()
  else
    rbuf = scratch('nice-git://' .. (rspec or 'deleted:' .. path), path, rlines)
    api.nvim_win_set_buf(main, rbuf)
  end
  local lbuf = scratch('nice-git://' .. (lspec or 'new:' .. path), path, llines)
  vim.cmd('leftabove vsplit')
  local lwin = api.nvim_get_current_win()
  api.nvim_win_set_buf(lwin, lbuf)

  for _, w in ipairs({ lwin, main }) do
    api.nvim_win_call(w, function()
      vim.cmd('diffthis')
    end)
    vim.wo[w].foldenable = false -- show the whole file, not just the hunks
  end
  sidebar.open_win()
  api.nvim_set_current_win(main)

  cur = {
    tab = api.nvim_get_current_tabpage(),
    root = state.root,
    left = { buf = lbuf, spec = lspec },
    right = { buf = rbuf, spec = rspec },
  }
end

function M.open(state, row)
  local lspec, rspec = specs(row.section, row.entry)
  load(state.root, lspec, function(llines)
    load(state.root, rspec, function(rlines)
      show(state, row.entry.path, lspec, rspec, llines, rlines)
    end)
  end)
end

---Re-reads the git-backed panes (e.g. after staging changed the index).
function M.refresh()
  if not (cur and api.nvim_tabpage_is_valid(cur.tab)) then
    return
  end
  for _, side in ipairs({ cur.left, cur.right }) do
    if type(side.spec) == 'string' and api.nvim_buf_is_valid(side.buf) then
      git.show(cur.root, side.spec, function(lines)
        if not api.nvim_buf_is_valid(side.buf) then
          return
        end
        set_lines(side.buf, lines)
        local win = vim.fn.win_findbuf(side.buf)[1]
        if win then
          api.nvim_win_call(win, function()
            vim.cmd('diffupdate')
          end)
        end
      end)
    end
  end
end

return M
