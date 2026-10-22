-- Commit graph in its own tab. Click a commit to list its files, click a file to diff it.
local api = vim.api
local git = require('nice-git.git')

local M = { limit = 300, all = false }

local ns = api.nvim_create_namespace('nice-git-log')

local GRAPH_HL = { 'NiceGitGraph1', 'NiceGitGraph2', 'NiceGitGraph3', 'NiceGitGraph4', 'NiceGitGraph5', 'NiceGitGraph6' }
local STATUS_HL = { A = 'NiceGitAdded', D = 'NiceGitDeleted' }

local items = {} -- parsed `git log --graph` lines: { graph, hash?, refs?, subject?, author?, date? }
local files = {} -- hash -> changed files, loaded on first expand
local expanded = {} -- hash -> true
local rows = {}

local function state()
  return require('nice-git').state
end

local function parse(out)
  local list = {}
  for _, line in ipairs(vim.split(out, '\n', { trimempty = true })) do
    local graph, rest = line:match('^(.-)\1(.*)$')
    if graph then
      local f = vim.split(rest, '\1', { plain = true })
      table.insert(list, { graph = graph, hash = f[1], refs = f[2], subject = f[3], author = f[4], date = f[5] })
    else
      table.insert(list, { graph = line })
    end
  end
  return list
end

-- Colors graph characters by column so parallel lines are easy to follow.
local function graph_hls(graph, hls)
  for i = 1, #graph do
    if graph:sub(i, i) ~= ' ' then
      table.insert(hls, { i - 1, i, GRAPH_HL[math.floor((i - 1) / 2) % #GRAPH_HL + 1] })
    end
  end
end

local function build()
  local out = {}
  local commits = 0
  for _, item in ipairs(items) do
    local hls = {}
    graph_hls(item.graph, hls)
    if not item.hash then
      table.insert(out, { text = item.graph, hls = hls })
    else
      commits = commits + 1
      local refs = item.refs ~= '' and '(' .. item.refs .. ') ' or ''
      local text = item.graph .. item.hash .. ' ' .. refs .. item.subject
      local h = #item.graph
      table.insert(hls, { h, h + #item.hash, 'NiceGitHash' })
      table.insert(hls, { h + #item.hash + 1, h + #item.hash + 1 + #refs, 'NiceGitRef' })
      table.insert(out, {
        text = text,
        hls = hls,
        commit = item,
        virt = { { item.author .. ', ' .. item.date .. ' ', 'NiceGitPath' } },
      })
      if expanded[item.hash] then
        -- Continue the graph's vertical lines alongside the file list.
        local prefix = item.graph:gsub('%*', '|'):gsub('[\\/_]', ' ')
        for _, f in ipairs(files[item.hash] or {}) do
          local line = prefix .. '   ' .. f.status .. ' ' .. f.path
          local fh = {}
          graph_hls(prefix, fh)
          table.insert(fh, { #prefix + 3, #prefix + 4, STATUS_HL[f.status] or 'NiceGitModified' })
          table.insert(out, { text = line, hls = fh, commit = item, file = f })
        end
      end
    end
  end
  if commits >= M.limit then
    table.insert(out, { text = '   … Load more', hls = { { 0, 17, 'NiceGitButton' } }, more = true })
  elseif #items == 0 then
    table.insert(out, { text = '   No commits yet', hls = { { 0, 19, 'NiceGitEmpty' } } })
  end
  return out
end

local function render()
  local buf = M.buf
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return
  end
  rows = build()
  local lines = {}
  for i, row in ipairs(rows) do
    lines[i] = row.text
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, row in ipairs(rows) do
    for _, h in ipairs(row.hls) do
      api.nvim_buf_set_extmark(buf, ns, i - 1, h[1], { end_col = h[2], hl_group = h[3] })
    end
    if row.virt then
      api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { virt_text = row.virt, virt_text_pos = 'right_align' })
    end
  end
end

-- Toolbar buttons call back through this global; winbar click handlers can't hold closures.
local toolbar = {}
_G.NiceGitLogClick = function(id)
  if toolbar[id] then
    vim.schedule(toolbar[id])
  end
end

local function set_toolbar()
  local function button(id, text)
    return ('%%%d@v:lua.NiceGitLogClick@%%#NiceGitToolbarButton# %s %%*%%X '):format(id, text)
  end
  local win = vim.fn.bufwinid(M.buf)
  if win ~= -1 then
    vim.wo[win].winbar = '%#NiceGitToolbarTitle# History %*%='
      .. button(1, (M.all and '☑' or '☐') .. ' All branches')
      .. button(2, '↻ Refresh')
  end
end

function M.refresh()
  if not (M.buf and api.nvim_buf_is_valid(M.buf) and state().root) then
    return
  end
  local args = { 'log', '--graph', '--date=relative', '--format=%x01%h%x01%D%x01%s%x01%an%x01%ad', '-n', tostring(M.limit) }
  if M.all then
    table.insert(args, '--all')
  end
  git.run(state().root, args, function(ok, out)
    items = ok and parse(out) or {}
    render()
    set_toolbar()
  end)
end

local function load_files(hash, cb)
  local args = { 'diff-tree', '--no-commit-id', '-r', '-M', '--name-status', '-z', '--root', '-m', '--first-parent', hash }
  git.run(state().root, args, function(_, out)
    local list, parts, i = {}, vim.split(out, '\0', { plain = true }), 1
    while i < #parts do
      local status = parts[i]:sub(1, 1)
      if status == 'R' or status == 'C' then
        table.insert(list, { status = status, orig = parts[i + 1], path = parts[i + 2], commit = hash })
        i = i + 3
      else
        table.insert(list, { status = status, path = parts[i + 1], commit = hash })
        i = i + 2
      end
    end
    files[hash] = list
    cb()
  end)
end

---@param root? string defaults to the active repository
function M.show_commit(hash, root)
  git.run(root or state().root, { 'show', '--stat', '--patch', hash }, function(ok, out)
    if ok then
      require('nice-git.diff').show_page('commit:' .. hash, vim.split(out, '\n', { plain = true }), 'git', 'Commit ' .. hash)
    end
  end)
end

local function activate(row)
  if row.more then
    M.limit = M.limit + 300
    M.refresh()
  elseif row.file then
    require('nice-git.diff').open(state(), { section = 'commit', entry = row.file })
  elseif row.commit then
    local hash = row.commit.hash
    expanded[hash] = not expanded[hash] or nil
    if expanded[hash] and not files[hash] then
      load_files(hash, render)
    else
      render()
    end
  end
end

local function menu(row)
  if not (row and row.commit) then
    return
  end
  local hash = row.commit.hash
  local choices = {
    { 'Show commit', function() M.show_commit(hash) end },
    { 'Copy hash', function()
      vim.fn.setreg('+', hash)
      vim.fn.setreg('"', hash)
    end },
  }
  vim.list_extend(choices, M.extra_menu or {})
  vim.ui.select(choices, {
    prompt = hash .. ' ' .. row.commit.subject,
    format_item = function(c)
      return c[1]
    end,
  }, function(choice)
    if choice then
      choice[2](hash, row.commit)
    end
  end)
end

local function row_under_mouse()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= 0 and api.nvim_win_get_buf(pos.winid) == M.buf and pos.line > 0 then
    return rows[pos.line]
  end
end

local function cursor_row()
  return rows[api.nvim_win_get_cursor(0)[1]]
end

local function ensure_buf()
  if M.buf and api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, 'nice-git://log')
  vim.bo[buf].filetype = 'nice-git-log'
  vim.bo[buf].modifiable = false
  M.buf = buf
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  for _, n in ipairs({ '', '2-', '3-', '4-' }) do
    map('<' .. n .. 'LeftRelease>', function()
      local row = row_under_mouse()
      if row then
        activate(row)
      end
    end)
    map('<' .. n .. 'LeftDrag>', '<Nop>')
  end
  map('<RightMouse>', function()
    local pos = vim.fn.getmousepos()
    if pos.winid ~= 0 and pos.line > 0 then
      api.nvim_set_current_win(pos.winid)
      api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })
    end
    menu(row_under_mouse())
  end)
  map('<CR>', function()
    local row = cursor_row()
    if row then
      activate(row)
    end
  end, 'Expand commit / open file')
  map('m', function()
    menu(cursor_row())
  end, 'Commit menu')
  map('o', function()
    local row = cursor_row()
    if row and row.commit then
      M.show_commit(row.commit.hash)
    end
  end, 'Show commit')
  map('y', function()
    local row = cursor_row()
    if row and row.commit then
      vim.fn.setreg('+', row.commit.hash)
      vim.fn.setreg('"', row.commit.hash)
    end
  end, 'Copy hash')
  map('q', function()
    vim.cmd('tabclose')
  end, 'Close')
  return buf
end

toolbar[1] = function()
  M.all = not M.all
  M.refresh()
end
toolbar[2] = M.refresh

function M.open()
  require('nice-git').with_root(M.show)
end

function M.show()
  local buf = ensure_buf()
  local win = vim.fn.win_findbuf(buf)[1]
  if win then
    api.nvim_set_current_win(win)
  else
    vim.cmd('tabnew')
    api.nvim_win_set_buf(0, buf)
    local wo = vim.wo[0]
    wo.number, wo.relativenumber, wo.wrap, wo.list, wo.spell = false, false, false, false, false
    wo.signcolumn, wo.cursorline = 'no', true
  end
  M.refresh()
end

return M
