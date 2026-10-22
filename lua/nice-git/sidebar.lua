-- Source Control panel: one buffer, shown in a left split of every tab that asks for it.
local api = vim.api
local git = require('nice-git.git')

local M = {}

local ns = api.nvim_create_namespace('nice-git')
local ns_drop = api.nvim_create_namespace('nice-git-drop')

local SECTIONS = {
  { key = 'staged', title = 'STAGED CHANGES' },
  { key = 'changes', title = 'CHANGES' },
  { key = 'untracked', title = 'UNTRACKED' },
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
  NiceGitPlaceholder = 'Comment',
  NiceGitButton = 'Special',
  NiceGitCommitButton = 'PmenuSel',
  NiceGitAdded = 'Added',
  NiceGitModified = 'Changed',
  NiceGitDeleted = 'Removed',
  NiceGitConflict = 'DiagnosticError',
  NiceGitDropTarget = 'Visual',
  NiceGitInlineAdd = 'DiffAdd',
  NiceGitInlineDelete = 'DiffDelete',
  NiceGitConflictOurs = 'DiffAdd',
  NiceGitConflictTheirs = 'DiffChange',
  NiceGitConflictBase = 'DiffText',
  NiceGitConflictMarker = 'Comment',
  NiceGitConflictButton = 'PmenuSel',
  NiceGitOperation = 'DiagnosticWarn',
  NiceGitHash = 'Identifier',
  NiceGitRef = 'Label',
  NiceGitGraph1 = 'DiagnosticInfo',
  NiceGitGraph2 = 'DiagnosticHint',
  NiceGitGraph3 = 'DiagnosticWarn',
  NiceGitGraph4 = 'Special',
  NiceGitGraph5 = 'Constant',
  NiceGitGraph6 = 'Function',
  NiceGitToolbar = 'WinBar',
  NiceGitToolbarTitle = 'WinBar',
  NiceGitToolbarButton = 'TabLine',
}

function M.set_highlights()
  for name, link in pairs(HIGHLIGHTS) do
    api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

M.collapsed = {}
M.rows = {}

-- Width in cells of every right-aligned button label; clicks are mapped back by position.
local BUTTON_WIDTH = 3

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

local function notify_result(ok, out, err)
  if not ok then
    vim.notify('nice-git: ' .. vim.trim(err ~= '' and err or out), vim.log.levels.ERROR)
  end
  require('nice-git').refresh()
end

function M.win_in_tab()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(w) == M.buf then
      return w
    end
  end
end

-- Stage or unstage a file row, or a whole section when given a section row.
local function toggle_stage(row)
  local st = state()
  local entries = row.entry and { row.entry } or st.status[row.section]
  if row.section == 'staged' then
    git.unstage(st.root, entries, st.status.has_head, notify_result)
  else
    git.stage(st.root, entries, notify_result)
  end
end

-- Throws away changes of a file row or a whole section; untracked files are deleted.
local function discard(row)
  local st = state()
  local entries = row.entry and { row.entry } or st.status[row.section]
  local what = row.entry and row.entry.path or (#entries .. ' files')
  local untracked = row.section == 'untracked'
  local prompt = untracked and ('Delete ' .. what .. '? This cannot be undone.') or ('Discard changes to ' .. what .. '?')
  if vim.fn.confirm(prompt, '&Discard\n&Cancel', 2) ~= 1 then
    return
  end
  if untracked then
    for _, e in ipairs(entries) do
      os.remove(st.root .. '/' .. e.path)
    end
    vim.cmd.checktime()
    require('nice-git').refresh()
  else
    git.discard(st.root, entries, function(...)
      vim.cmd.checktime()
      notify_result(...)
    end)
  end
end

---Rows are plain tables:
---  text, hls = { {start_col, end_col, group} }, click = fn(row)
---  virt = { {text, group} }        non-clickable right-aligned chunks (e.g. status letter)
---  right = { {label, group, fn} }  right-aligned buttons, each BUTTON_WIDTH cells
---  buttons = { {start_col, end_col, fn} }  clickable byte ranges of `text`
---  section, entry                  for staging and drag and drop
local function build()
  local st = state().status
  local commit = require('nice-git.commit')
  local rows = {}
  local function add(row)
    row.hls = row.hls or {}
    table.insert(rows, row)
    return row
  end

  local actions = require('nice-git.actions')
  local branch = ' ⎇ ' .. (st.branch == '(detached)' and 'detached HEAD' or st.branch or '?')
  local head = branch
  if st.ahead then
    head = head .. ('  ↑%d ↓%d'):format(st.ahead, st.behind)
  end
  if actions.busy then
    head = head .. '  ' .. actions.busy .. '…'
  end
  add({
    text = head,
    hls = { { 0, #branch, 'NiceGitHeader' }, { #branch, #head, 'NiceGitCount' } },
    buttons = { { 0, #branch, actions.switch_branch } },
    right = {
      { ' ☰ ', 'NiceGitButton', require('nice-git.log').open },
      { ' ⟳ ', 'NiceGitButton', actions.fetch },
      { ' ↓ ', 'NiceGitButton', actions.pull },
      { ' ↑ ', 'NiceGitButton', actions.push },
    },
  })

  if st.operation then
    local label = ' ⚠ ' .. st.operation:upper() .. ' '
    local line, buttons = label, {}
    local ops = { { ' Continue ', actions.continue }, { ' Abort ', actions.abort } }
    if st.operation == 'rebase' or st.operation == 'cherry-pick' then
      table.insert(ops, 2, { ' Skip ', actions.skip })
    end
    local hls = { { 0, #label, 'NiceGitOperation' } }
    for _, op in ipairs(ops) do
      line = line .. ' '
      table.insert(buttons, { #line, #line + #op[1], op[2] })
      table.insert(hls, { #line, #line + #op[1], 'NiceGitButton' })
      line = line .. op[1]
    end
    add({ text = line, hls = hls, buttons = buttons })
  end

  local btn = ' ✓ Commit '
  local amend = commit.amend and ' ☑ Amend ' or ' ☐ Amend '
  local stash = ' ⊟ Stash '
  local text = ' ' .. btn .. ' ' .. amend .. ' ' .. stash
  local a = 1 + #btn + 1
  local s = a + #amend + 1
  add({
    text = text,
    hls = { { 1, 1 + #btn, 'NiceGitCommitButton' }, { a, a + #amend, 'NiceGitButton' }, { s, #text, 'NiceGitButton' } },
    buttons = { { 1, 1 + #btn, commit.commit }, { a, a + #amend, commit.toggle_amend }, { s, #text, actions.stash } },
  })

  local any = false
  for _, sec in ipairs(SECTIONS) do
    local entries = st[sec.key]
    if #entries > 0 then
      any = true
      local right = sec.key == 'staged' and { { ' − ', 'NiceGitButton', toggle_stage } }
        or { { ' ↺ ', 'NiceGitButton', discard }, { ' + ', 'NiceGitButton', toggle_stage } }
      local title = (M.collapsed[sec.key] and ' ▸ ' or ' ▾ ') .. sec.title
      add({
        text = title,
        section = sec.key,
        hls = { { 0, #title, 'NiceGitSection' } },
        virt = { { ' ' .. #entries .. ' ', 'NiceGitCount' } },
        right = right,
        click = function()
          M.collapsed[sec.key] = not M.collapsed[sec.key]
          M.render()
        end,
      })
      if not M.collapsed[sec.key] then
        for _, e in ipairs(entries) do
          local icon, icon_hl = file_icon(e.path)
          local name = vim.fs.basename(e.path)
          local dir = vim.fs.dirname(e.path)
          local st_char, st_hl = unpack(STATUS[e.status] or { e.status, 'NiceGitModified' })
          local prefix = '   ' .. icon .. ' '
          local line = prefix .. name .. (dir ~= '.' and ' ' .. dir or '')
          add({
            text = line,
            section = sec.key,
            entry = e,
            hls = {
              { 3, #prefix - 1, icon_hl },
              { #prefix, #prefix + #name, st_hl },
              { #prefix + #name, #line, 'NiceGitPath' },
            },
            virt = { { st_char .. ' ', st_hl } },
            right = right,
            click = function(row)
              require('nice-git.diff').open(state(), row)
            end,
          })
        end
      end
    end
  end
  if not any then
    add({ text = '   No changes', hls = { { 0, 13, 'NiceGitEmpty' } } })
  end

  local stashes = st.stashes or {}
  if #stashes > 0 then
    local title = (M.collapsed.stashes and ' ▸ ' or ' ▾ ') .. 'STASHES'
    add({
      text = title,
      hls = { { 0, #title, 'NiceGitSection' } },
      virt = { { ' ' .. #stashes .. ' ', 'NiceGitCount' } },
      click = function()
        M.collapsed.stashes = not M.collapsed.stashes
        M.render()
      end,
    })
    if not M.collapsed.stashes then
      for _, stash in ipairs(stashes) do
        local line = '   ≡ ' .. stash.message
        add({
          text = line,
          stash = stash,
          hls = { { 3, 6, 'NiceGitPath' } },
          right = {
            { ' ↓ ', 'NiceGitButton', function() actions.stash_apply(stash) end },
            { ' ✕ ', 'NiceGitButton', function() actions.stash_drop(stash) end },
          },
          click = function()
            actions.show_stash(stash)
          end,
        })
      end
    end
  end
  return rows
end

function M.render()
  local buf = M.buf
  if not (buf and api.nvim_buf_is_valid(buf) and state().status) then
    return
  end
  local rows = build()
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
    local virt = vim.list_extend({}, row.virt or {})
    for _, b in ipairs(row.right or {}) do
      table.insert(virt, { b[1], b[2] })
    end
    if #virt > 0 then
      api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { virt_text = virt, virt_text_pos = 'right_align' })
    end
  end
  M.rows = rows
  require('nice-git.commit').update_placeholder()
end

local function row_at(pos)
  if pos.winid ~= 0 and api.nvim_win_get_buf(pos.winid) == M.buf and pos.line > 0 then
    return M.rows[pos.line]
  end
end

local function cursor_row()
  return M.rows[api.nvim_win_get_cursor(0)[1]]
end

-- Runs whatever sits under the mouse: a right-aligned button, a text button, or the row itself.
local function click(row, pos)
  local from_right = api.nvim_win_get_width(pos.winid) - pos.wincol
  local right = row.right or {}
  local idx = #right - math.floor(from_right / BUTTON_WIDTH)
  if idx >= 1 and idx <= #right then
    return right[idx][3](row)
  end
  for _, b in ipairs(row.buttons or {}) do
    if pos.column > b[1] and pos.column <= b[2] then
      return b[3](row)
    end
  end
  if row.click then
    row.click(row)
  end
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
  for l, row in ipairs(M.rows) do
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
      toggle_stage(d.row)
    end
    return
  end
  click(row, pos)
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

  local function map(modes, lhs, rhs, desc, opts)
    opts = vim.tbl_extend('force', { buffer = buf, nowait = true, silent = true, desc = desc }, opts or {})
    vim.keymap.set(modes, lhs, rhs, opts)
  end
  local function with_row(fn)
    return function()
      local row = cursor_row()
      if row then
        fn(row)
      end
    end
  end
  -- Quick repeated clicks arrive as <2-LeftMouse> etc.; each one should act like a single click.
  for _, n in ipairs({ '', '2-', '3-', '4-' }) do
    map('n', '<' .. n .. 'LeftMouse>', on_mouse, nil, { expr = true })
    map('n', '<' .. n .. 'LeftDrag>', on_drag, nil, { expr = true })
    map({ 'n', 'i' }, '<' .. n .. 'LeftRelease>', on_release)
  end
  map('n', '<CR>', with_row(function(row)
    if row.click then
      row.click(row)
    end
  end), 'Open diff / toggle section')
  map('n', '-', with_row(function(row)
    if row.section then
      toggle_stage(row)
    end
  end), 'Stage / unstage')
  map('n', 'x', with_row(function(row)
    if row.section and row.section ~= 'staged' then
      discard(row)
    end
  end), 'Discard changes')
  local actions = require('nice-git.actions')
  map('n', 'b', actions.switch_branch, 'Switch branch')
  map('n', 'l', require('nice-git.log').open, 'History')
  map('n', 'f', actions.fetch, 'Fetch')
  map('n', 'p', actions.pull, 'Pull')
  map('n', 'P', actions.push, 'Push')
  map('n', 'c', function()
    require('nice-git.commit').focus()
  end, 'Write commit message')
  map('n', 'R', function()
    require('nice-git').refresh()
  end, 'Refresh')
  map('n', 'q', M.close, 'Close panel')

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
  M.set_highlights()
  api.nvim_create_autocmd('ColorScheme', { buffer = buf, callback = M.set_highlights })
  return buf
end

---Opens the panel (commit box above the file list) as a full-height left column in the current
---tab and returns the file list window.
function M.open_win()
  local buf = ensure_buf()
  local win = M.win_in_tab()
  if not win then
    win = api.nvim_open_win(buf, true, { split = 'left', win = -1, width = require('nice-git').config.width })
    local wo = vim.wo[win]
    wo.number, wo.relativenumber, wo.spell, wo.list, wo.wrap = false, false, false, false, false
    wo.signcolumn, wo.foldcolumn, wo.statuscolumn = 'no', '0', ''
    wo.cursorline, wo.winfixwidth, wo.winfixbuf = true, true, true
  end
  require('nice-git.commit').open_win(win)
  if not state().status then
    require('nice-git').refresh()
  end
  return win
end

function M.close()
  local commit_win = require('nice-git.commit').win_in_tab()
  if commit_win then
    pcall(api.nvim_win_close, commit_win, false)
  end
  local win = M.win_in_tab()
  if win and not pcall(api.nvim_win_close, win, false) then
    vim.notify('nice-git: cannot close the last window', vim.log.levels.WARN)
  end
end

return M
