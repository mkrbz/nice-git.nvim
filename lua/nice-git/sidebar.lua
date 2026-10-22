-- Source Control panel: one buffer, shown in a left split of every tab that asks for it.
local api = vim.api
local git = require('nice-git.git')

local M = {}

local ns = api.nvim_create_namespace('nice-git')
local ns_drop = api.nvim_create_namespace('nice-git-drop')

local SECTIONS = {
  { key = 'staged', title = 'STAGED CHANGES', button = ' − ' },
  { key = 'changes', title = 'CHANGES', button = ' + ' },
  { key = 'untracked', title = 'UNTRACKED', button = ' + ' },
}

local STATUS = {
  A = { 'A', 'NiceGitAdded' },
  ['?'] = { 'U', 'NiceGitAdded' },
  M = { 'M', 'NiceGitModified' },
  T = { 'T', 'NiceGitModified' },
  R = { 'R', 'NiceGitModified' },
  C = { 'C', 'NiceGitModified' },
  D = { 'D', 'NiceGitDeleted' },
  U = { '!', 'NiceGitConflict' },
}

local HIGHLIGHTS = {
  NiceGitHeader = 'Title',
  NiceGitSection = 'Statement',
  NiceGitCount = 'Comment',
  NiceGitPath = 'Comment',
  NiceGitEmpty = 'Comment',
  NiceGitButton = 'Special',
  NiceGitAdded = 'Added',
  NiceGitModified = 'Changed',
  NiceGitDeleted = 'Removed',
  NiceGitConflict = 'DiagnosticError',
  NiceGitDropTarget = 'Visual',
}

local function set_highlights()
  for name, link in pairs(HIGHLIGHTS) do
    api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

M.collapsed = {}
M.rows = {}

local icon_provider
local function file_icon(path)
  if icon_provider == nil then
    local ok, devicons = pcall(require, 'nvim-web-devicons')
    if _G.MiniIcons then
      icon_provider = function(name)
        return _G.MiniIcons.get('file', name)
      end
    elseif ok then
      icon_provider = function(name)
        return devicons.get_icon(name, nil, { default = true })
      end
    else
      icon_provider = false
    end
  end
  if not icon_provider then
    return '•', 'NiceGitPath'
  end
  return icon_provider(vim.fs.basename(path))
end

local function state()
  return require('nice-git').state
end

function M.wins()
  return M.buf and api.nvim_buf_is_valid(M.buf) and vim.fn.win_findbuf(M.buf) or {}
end

function M.win_in_tab()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(w) == M.buf then
      return w
    end
  end
end

function M.render()
  local buf, st = M.buf, state().status
  if not (buf and api.nvim_buf_is_valid(buf) and st) then
    return
  end
  local lines, rows, marks = {}, {}, {}
  local function add(text, row, hls, virt)
    table.insert(lines, text)
    rows[#lines] = row
    marks[#lines] = { hls = hls or {}, virt = virt }
  end

  local head = ' ⎇ ' .. (st.branch == '(detached)' and 'detached HEAD' or st.branch or '?')
  if st.ahead then
    head = head .. ('  ↑%d ↓%d'):format(st.ahead, st.behind)
  end
  add(head, { kind = 'header' }, { { 0, #head, 'NiceGitHeader' } })

  local any = false
  for _, sec in ipairs(SECTIONS) do
    local entries = st[sec.key]
    if #entries > 0 then
      any = true
      local text = (M.collapsed[sec.key] and ' ▸ ' or ' ▾ ') .. sec.title
      add(text, { kind = 'section', section = sec.key }, { { 0, #text, 'NiceGitSection' } }, {
        { ' ' .. #entries .. ' ', 'NiceGitCount' },
        { sec.button, 'NiceGitButton' },
      })
      if not M.collapsed[sec.key] then
        for _, e in ipairs(entries) do
          local icon, icon_hl = file_icon(e.path)
          local name = vim.fs.basename(e.path)
          local dir = vim.fs.dirname(e.path)
          local st_char, st_hl = unpack(STATUS[e.status] or { e.status, 'NiceGitModified' })
          local prefix = '   ' .. icon .. ' '
          local text = prefix .. name .. (dir ~= '.' and ' ' .. dir or '')
          add(text, { kind = 'file', section = sec.key, entry = e }, {
            { 3, #prefix - 1, icon_hl },
            { #prefix, #prefix + #name, st_hl },
            { #prefix + #name, #text, 'NiceGitPath' },
          }, { { st_char .. ' ', st_hl }, { sec.button, 'NiceGitButton' } })
        end
      end
    end
  end
  if not any then
    add('   No changes', { kind = 'empty' }, { { 0, 13, 'NiceGitEmpty' } })
  end

  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for l, m in ipairs(marks) do
    for _, h in ipairs(m.hls) do
      api.nvim_buf_set_extmark(buf, ns, l - 1, h[1], { end_col = h[2], hl_group = h[3] })
    end
    if m.virt then
      api.nvim_buf_set_extmark(buf, ns, l - 1, 0, { virt_text = m.virt, virt_text_pos = 'right_align' })
    end
  end
  M.rows = rows
end

-- Stage or unstage a file row, or a whole section when given a section row.
local function act(row)
  local st = state()
  local entries = row.entry and { row.entry } or st.status[row.section]
  local function done(ok, _, err)
    if not ok then
      vim.notify('nice-git: ' .. vim.trim(err), vim.log.levels.ERROR)
    end
    require('nice-git').refresh()
  end
  if row.section == 'staged' then
    git.unstage(st.root, entries, st.status.has_head, done)
  else
    git.stage(st.root, entries, done)
  end
end

local function activate(row)
  if row.kind == 'section' then
    M.collapsed[row.section] = not M.collapsed[row.section]
    M.render()
  elseif row.kind == 'file' then
    require('nice-git.diff').open(state(), row)
  end
end

local function row_at(pos)
  if pos.winid ~= 0 and api.nvim_win_get_buf(pos.winid) == M.buf and pos.line > 0 then
    return M.rows[pos.line]
  end
end

local function cursor_row()
  return M.rows[api.nvim_win_get_cursor(0)[1]]
end

-- Dropping onto the other side of the staged/unstaged divide is the only meaningful move.
local function crosses(from, to)
  return to and to.section and (from.section == 'staged') ~= (to.section == 'staged')
end

-- { row, moved } while dragging a file; false after a press elsewhere in the panel; nil when the
-- press happened in another window (our <LeftMouse> mapping only fires once the panel has focus).
local drag

local function show_drop_target(target)
  api.nvim_buf_clear_namespace(M.buf, ns_drop, 0, -1)
  if not (drag and crosses(drag.row, target)) then
    return
  end
  for l, row in pairs(M.rows) do
    if row.section == target.section then
      api.nvim_buf_set_extmark(M.buf, ns_drop, l - 1, 0, { line_hl_group = 'NiceGitDropTarget' })
    end
  end
end

local function on_mouse()
  local pos = vim.fn.getmousepos()
  local row = pos.wincol <= api.nvim_win_get_width(pos.winid) and row_at(pos) -- not the separator
  drag = row and row.entry and { row = row, moved = false } or false
  return '<LeftMouse>'
end

local function on_drag()
  if drag == nil then
    -- Pressed while another window had focus: the default click already put the cursor on the row.
    local row = cursor_row()
    drag = row and row.entry and { row = row, moved = false } or false
  end
  if not drag then
    return '<LeftDrag>' -- e.g. resizing the window separator
  end
  drag.moved = true
  local target = row_at(vim.fn.getmousepos())
  vim.schedule(function()
    show_drop_target(target)
  end)
  return ''
end

-- Clicks are handled on release so a click from another window (which first focuses the panel)
-- still acts in one go, and so a press can turn into a drag.
local function on_release()
  if vim.fn.mode() == 'i' then
    vim.cmd.stopinsert()
  end
  local pos = vim.fn.getmousepos()
  local d = drag
  drag = nil
  api.nvim_buf_clear_namespace(M.buf, ns_drop, 0, -1)
  local row = row_at(pos)
  if not row then
    return
  end
  if d and d.moved then
    if crosses(d.row, row) then
      act(d.row)
    end
    return
  end
  if (row.kind == 'file' or row.kind == 'section') and pos.wincol >= api.nvim_win_get_width(pos.winid) - 2 then
    act(row)
  else
    activate(row)
  end
end

local function ensure_buf()
  if M.buf and api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, 'nice-git://status')
  vim.bo[buf].filetype = 'nice-git'
  vim.bo[buf].modifiable = false
  M.buf = buf

  local function map(modes, lhs, rhs, opts)
    opts = vim.tbl_extend('force', { buffer = buf, nowait = true, silent = true }, opts or {})
    vim.keymap.set(modes, lhs, rhs, opts)
  end
  map('n', '<LeftMouse>', on_mouse, { expr = true })
  map('n', '<LeftDrag>', on_drag, { expr = true })
  map({ 'n', 'i' }, '<LeftRelease>', on_release)
  map('n', '<2-LeftMouse>', '<Nop>')
  map('n', '<CR>', function()
    local row = cursor_row()
    if row then
      activate(row)
    end
  end, { desc = 'Open diff / toggle section' })
  map('n', '-', function()
    local row = cursor_row()
    if row and row.section then
      act(row)
    end
  end, { desc = 'Stage / unstage' })
  map('n', 'R', function()
    require('nice-git').refresh()
  end, { desc = 'Refresh' })
  map('n', 'q', M.close, { desc = 'Close panel' })

  -- Watch the repo only while the panel is visible somewhere.
  api.nvim_create_autocmd('BufWinEnter', {
    buffer = buf,
    callback = function()
      require('nice-git').watch()
    end,
  })
  api.nvim_create_autocmd('BufWinLeave', {
    buffer = buf,
    callback = function()
      require('nice-git').unwatch()
    end,
  })
  set_highlights()
  api.nvim_create_autocmd('ColorScheme', { buffer = buf, callback = set_highlights })
  return buf
end

---Opens the panel as a full-height left split in the current tab and returns its window.
function M.open_win()
  local buf = ensure_buf()
  local win = M.win_in_tab()
  if win then
    return win
  end
  vim.cmd('topleft vsplit')
  win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)
  api.nvim_win_set_width(win, require('nice-git').config.width)
  local wo = vim.wo[win]
  wo.number, wo.relativenumber, wo.spell, wo.list, wo.wrap = false, false, false, false, false
  wo.signcolumn, wo.foldcolumn, wo.statuscolumn = 'no', '0', ''
  wo.cursorline, wo.winfixwidth, wo.winfixbuf = true, true, true
  return win
end

function M.close()
  local win = M.win_in_tab()
  if win and not pcall(api.nvim_win_close, win, false) then
    vim.notify('nice-git: cannot close the last window', vim.log.levels.WARN)
  end
end

return M
