-- Commit graph in its own tab. Click a commit to list its files, click a file to diff it.
local api = vim.api
local git = require('nice-git.git')
local theme = require('nice-git.theme')
local ui = require('nice-git.ui')

local M = { limit = 300, all = false }

local ns = api.nvim_create_namespace('nice-git-log')
local ns_hover = api.nvim_create_namespace('nice-git-log-hover')

local LANE_HL = { 'NiceGitGraph1', 'NiceGitGraph2', 'NiceGitGraph3', 'NiceGitGraph4', 'NiceGitGraph5', 'NiceGitGraph6' }
local STATUS_HL = { A = 'NiceGitAdded', D = 'NiceGitDeleted', R = 'NiceGitModified', M = 'NiceGitModified' }

local commits = {} -- { hash, short, parents, refs, subject, author, time }
local files = {} -- hash -> changed files, loaded on first expand
local expanded = {} -- hash -> true
local rows = {}

local function state()
  return require('nice-git').state
end

local function lane_hl(j)
  return LANE_HL[(j - 1) % #LANE_HL + 1]
end

local function parse(out)
  local list = {}
  for _, line in ipairs(vim.split(out, '\n', { trimempty = true })) do
    local f = vim.split(line, '\0', { plain = true })
    table.insert(list, {
      hash = f[1],
      short = f[2],
      parents = vim.split(f[3], ' ', { trimempty = true }),
      refs = f[4],
      subject = f[5],
      author = f[6],
      time = tonumber(f[7]),
    })
  end
  return list
end

---Lays out one row per commit. Each lane holds the hash it is waiting for. Returns per commit
---{ cells = { {glyph, hl, link_hl} per lane }, after = { {glyph, hl} } for the lanes open below it }.
local function layout(list)
  local lanes, out = {}, {}
  local function free_slot(from)
    for j = from or 1, #lanes + 1 do
      if lanes[j] == nil then
        return j
      end
    end
  end
  for _, c in ipairs(list) do
    local col
    for j = 1, #lanes do
      if lanes[j] == c.hash then
        col = col or j
      end
    end
    col = col or free_slot()
    lanes[col] = c.hash
    local width = #lanes
    local glyph, link = {}, {} -- link[j]: horizontal line between lane j and j+1
    for j = 1, width do
      if j == col then
        glyph[j] = { '●', lane_hl(j) }
      elseif lanes[j] == c.hash then -- another branch line ends in this commit
        glyph[j] = { j > col and '╯' or '╰', lane_hl(j) }
        for k = math.min(j, col), math.max(j, col) - 1 do
          link[k] = lane_hl(j)
        end
        lanes[j] = nil
      elseif lanes[j] then
        glyph[j] = { '│', lane_hl(j) }
      else
        glyph[j] = { ' ' }
      end
    end
    lanes[col] = c.parents[1]
    for p = 2, #c.parents do
      local k
      for j = 1, #lanes do
        if lanes[j] == c.parents[p] then
          k = j
        end
      end
      if not k then
        k = free_slot(col + 1)
        lanes[k] = c.parents[p]
        glyph[k] = { k > col and '╮' or '╭', lane_hl(k) }
      end
      for j = math.min(k, col), math.max(k, col) - 1 do
        link[j] = link[j] or lane_hl(k)
      end
    end
    while #lanes > 0 and lanes[#lanes] == nil do
      lanes[#lanes] = nil
    end
    local cells = {}
    for j = 1, math.max(width, #lanes) do
      local g = glyph[j] or { ' ' }
      cells[j] = { g[1], g[2], link[j] }
    end
    local after = {}
    for j = 1, #lanes do
      after[j] = lanes[j] and { '│', lane_hl(j) } or { ' ' }
    end
    table.insert(out, { cells = cells, after = after })
  end
  return out
end

-- Appends graph cells (glyph + connector per lane) to `text`, recording highlight spans.
local function draw_cells(text, hls, cells)
  for _, cell in ipairs(cells) do
    local start = #text
    text = text .. cell[1]
    if cell[2] then
      table.insert(hls, { start, #text, cell[2] })
    end
    start = #text
    text = text .. (cell[3] and '─' or ' ')
    if cell[3] then
      table.insert(hls, { start, #text, cell[3] })
    end
  end
  return text
end

local function pill(text, hls, label, body)
  local i = theme.icons
  for _, part in ipairs({ { i.pill_left, body .. 'Edge' }, { ' ' .. label .. ' ', body }, { i.pill_right, body .. 'Edge' } }) do
    local s = #text
    text = text .. part[1]
    table.insert(hls, { s, #text, part[2] })
  end
  return text
end

-- Ref names as pills: HEAD's branch in the accent color, other branches, remotes and tags soft.
local function draw_refs(text, hls, refs)
  local i = theme.icons
  for ref in vim.gsplit(refs, ', ', { plain = true, trimempty = true }) do
    local head = ref:match('^HEAD %-> (.+)$')
    local tag = ref:match('^tag: (.+)$')
    if head then
      text = pill(text, hls, i.branch .. ' ' .. head, 'NiceGitPill')
    elseif tag then
      text = pill(text, hls, i.tag .. ' ' .. tag, 'NiceGitPillSoft')
    elseif ref == 'HEAD' then
      text = pill(text, hls, 'HEAD', 'NiceGitPill')
    else
      text = pill(text, hls, (ref:find('/') and i.repo or i.branch) .. ' ' .. ref, 'NiceGitPillSoft')
    end
    text = text .. ' '
  end
  return text
end

local function file_icon(path)
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if _G.MiniIcons then
    return _G.MiniIcons.get('file', vim.fs.basename(path))
  elseif ok then
    return devicons.get_icon(vim.fs.basename(path), nil, { default = true })
  end
  return theme.icons.file, 'NiceGitDim'
end

local function build()
  local out = {}
  local graph = layout(commits)
  for n, c in ipairs(commits) do
    local hls = {}
    local text = draw_refs(draw_cells(' ', hls, graph[n].cells) .. ' ', hls, c.refs)
    text = text .. c.subject
    table.insert(out, {
      text = text,
      hls = hls,
      commit = c,
      virt = {
        { c.author .. '  ', 'NiceGitDim' },
        { ui.ago(c.time) .. '  ', 'NiceGitDim' },
        { c.short .. ' ', 'NiceGitAccent' },
      },
    })
    if expanded[c.hash] then
      for _, f in ipairs(files[c.hash] or {}) do
        local fh = {}
        local line = draw_cells(' ', fh, graph[n].after) .. '  '
        local icon, icon_hl = file_icon(f.path)
        local s = #line
        line = line .. icon .. ' '
        table.insert(fh, { s, s + #icon, icon_hl or 'NiceGitDim' })
        s = #line
        line = line .. f.status .. ' ' .. f.path
        table.insert(fh, { s, s + 1, STATUS_HL[f.status] or 'NiceGitModified' })
        table.insert(out, { text = line, hls = fh, commit = c, file = f })
      end
    end
  end
  if #commits >= M.limit then
    local hls = {}
    table.insert(out, { text = pill('   ', hls, 'Load more', 'NiceGitPillSoft'), hls = hls, more = true })
  elseif #commits == 0 then
    table.insert(out, { text = '   No commits yet', hls = { { 0, 19, 'NiceGitDim' } } })
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
      api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { virt_text = row.virt, virt_text_pos = 'right_align', hl_mode = 'combine' })
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
  local i = theme.icons
  local function button(id, text)
    return ('%%%d@v:lua.NiceGitLogClick@%%#NiceGitPillSoftEdge#%s%%#NiceGitPillSoft# %s %%#NiceGitPillSoftEdge#%s%%X%%#NiceGitToolbar# '):format(
      id, i.pill_left, text, i.pill_right)
  end
  local win = vim.fn.bufwinid(M.buf)
  if win ~= -1 then
    local repo = vim.fs.basename(state().root or ''):gsub('%%', '%%%%')
    vim.wo[win].winbar = '%#NiceGitPanelTitle#  ' .. i.history .. ' HISTORY %#NiceGitDim#' .. repo
      .. '%=%#NiceGitToolbar#'
      .. button(1, (M.all and '☑' or '☐') .. ' All branches')
      .. button(2, i.refresh .. ' Refresh')
  end
end

function M.refresh()
  if not (M.buf and api.nvim_buf_is_valid(M.buf) and state().root) then
    return
  end
  local args = { 'log', '--topo-order', '--format=%H%x00%h%x00%P%x00%D%x00%s%x00%an%x00%at', '-n', tostring(M.limit) }
  if M.all then
    table.insert(args, '--all')
  end
  git.run(state().root, args, function(ok, out)
    commits = ok and parse(out) or {}
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

local function copy(text)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
end

local function menu(row)
  if not (row and row.commit) then
    return
  end
  local i = theme.icons
  local hash = row.commit.short
  local choices = {
    { i.commit, 'Show commit', function()
      M.show_commit(hash)
    end },
    { i.copy, 'Copy hash', function()
      copy(hash)
    end },
    { i.edit, 'Interactive rebase from here…', function()
      require('nice-git.rebase').open(hash)
    end },
  }
  ui.select(choices, {
    prompt = hash .. ' ' .. row.commit.subject,
    format_item = function(c)
      return c[2]
    end,
    icon = function(c)
      return c[1]
    end,
  }, function(choice)
    if choice then
      choice[3]()
    end
  end)
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
  ui.clickable(buf, {
    click = function(pos)
      if rows[pos.line] then
        activate(rows[pos.line])
      end
    end,
    right_click = function(pos)
      menu(rows[pos.line])
    end,
  })
  ui.on_hover(buf, function(pos)
    api.nvim_buf_clear_namespace(buf, ns_hover, 0, -1)
    if pos and rows[pos.line] then
      api.nvim_buf_set_extmark(buf, ns_hover, pos.line - 1, 0, { line_hl_group = 'NiceGitHover', priority = 5 })
    end
  end)
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  local function with_commit(fn)
    return function()
      local row = cursor_row()
      if row and row.commit then
        fn(row)
      end
    end
  end
  map('<CR>', function()
    local row = cursor_row()
    if row then
      activate(row)
    end
  end, 'Expand commit / open file')
  map('m', with_commit(menu), 'Commit menu')
  map('o', with_commit(function(row)
    M.show_commit(row.commit.short)
  end), 'Show commit')
  map('y', with_commit(function(row)
    copy(row.commit.short)
  end), 'Copy hash')
  map('R', with_commit(function(row)
    require('nice-git.rebase').open(row.commit.short)
  end), 'Interactive rebase from here')
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
    theme.style_window(0, 'panel')
    vim.wo.wrap, vim.wo.cursorline = false, true
  end
  M.refresh()
end

return M
