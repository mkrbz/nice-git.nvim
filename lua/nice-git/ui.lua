-- Interactive building blocks shared by every view: toasts, hover tracking with tooltips, context
-- menus, input boxes, and click/drag handling for list-like buffers.
local api = vim.api
local theme = require('nice-git.theme')

local M = {}

-- Plain vim.notify / vim.ui.* when asked for, or when there is no UI to draw floats on.
local function native()
  return require('nice-git').config.native_ui or #api.nvim_list_uis() == 0
end

local function close_win(win)
  if win and api.nvim_win_is_valid(win) then
    pcall(api.nvim_win_close, win, true)
  end
end

local function scratch_buf(lines)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
  return buf
end

---"3 days ago" for a unix timestamp.
function M.ago(time)
  local d = os.time() - time
  for _, u in ipairs({ { 31536000, 'year' }, { 2592000, 'month' }, { 604800, 'week' }, { 86400, 'day' }, { 3600, 'hour' }, { 60, 'minute' } }) do
    if d >= u[1] then
      local n = math.floor(d / u[1])
      return n .. ' ' .. u[2] .. (n > 1 and 's' or '') .. ' ago'
    end
  end
  return 'just now'
end

-- Toasts ------------------------------------------------------------------------------------

local toasts = {}

local function restack()
  local row = vim.o.lines - vim.o.cmdheight - 2
  for i = #toasts, 1, -1 do
    local t = toasts[i]
    if api.nvim_win_is_valid(t.win) then
      api.nvim_win_set_config(t.win, { relative = 'editor', row = row, col = vim.o.columns - 2, anchor = 'SE' })
      row = row - t.height - 2
    end
  end
end

local function dismiss(t)
  for i, x in ipairs(toasts) do
    if x == t then
      table.remove(toasts, i)
      break
    end
  end
  close_win(t.win)
  restack()
end

---Shows a short-lived message in the bottom-right corner. Errors stay longer; click to dismiss.
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  if native() then
    return vim.notify('nice-git: ' .. msg, level)
  end
  local icon, hl = theme.icons.ok, 'NiceGitAdded'
  if level >= vim.log.levels.ERROR then
    icon, hl = theme.icons.error, 'NiceGitConflict'
  elseif level == vim.log.levels.WARN then
    icon, hl = theme.icons.warning, 'NiceGitModified'
  end
  local width = math.min(60, math.max(20, vim.o.columns - 10))
  local lines = {}
  for _, l in ipairs(vim.split(msg, '\n', { trimempty = true })) do
    while api.nvim_strwidth(l) > width - 4 do
      table.insert(lines, l:sub(1, width - 4))
      l = l:sub(width - 3)
    end
    table.insert(lines, l)
  end
  lines = vim.list_slice(lines, 1, 6)
  local text_width = 0
  for i, l in ipairs(lines) do
    lines[i] = (i == 1 and ' ' .. icon .. ' ' or '   ') .. l .. ' '
    text_width = math.max(text_width, api.nvim_strwidth(lines[i]))
  end
  local buf = scratch_buf(lines)
  api.nvim_buf_set_extmark(buf, api.nvim_create_namespace('nice-git-toast'), 0, 1, { end_col = 1 + #icon, hl_group = hl })
  local win = api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 0,
    col = 0,
    width = text_width,
    height = #lines,
    border = 'rounded',
    style = 'minimal',
    focusable = true,
    zindex = 250,
    noautocmd = true,
  })
  theme.style_window(win, 'toast')
  local t = { win = win, height = #lines }
  table.insert(toasts, t)
  restack()
  vim.keymap.set('n', '<LeftRelease>', function()
    vim.cmd('wincmd p')
    dismiss(t)
  end, { buffer = buf })
  vim.defer_fn(function()
    dismiss(t)
  end, level >= vim.log.levels.ERROR and 8000 or 3000)
end

-- Hover --------------------------------------------------------------------------------------

local hover_handlers = {} -- buf -> fn(pos | nil) returning an optional tooltip
local hovered -- { buf, line, tip }
local tooltip = {}
local saved_mousemev

local function hide_tooltip()
  if tooltip.timer then
    tooltip.timer:stop()
  end
  close_win(tooltip.win)
  tooltip.win = nil
end

local function show_tooltip(text, pos)
  hide_tooltip()
  tooltip.timer = tooltip.timer or assert(vim.uv.new_timer())
  tooltip.timer:start(500, 0, vim.schedule_wrap(function()
    local buf = scratch_buf({ ' ' .. text .. ' ' })
    local width = api.nvim_strwidth(text) + 2
    tooltip.win = api.nvim_open_win(buf, false, {
      relative = 'editor',
      row = pos.screenrow,
      col = math.max(0, math.min(pos.screencol - 1, vim.o.columns - width - 2)),
      width = width,
      height = 1,
      border = 'rounded',
      style = 'minimal',
      focusable = false,
      zindex = 240,
      noautocmd = true,
    })
    theme.style_window(tooltip.win, 'toast')
  end))
end

local function update_hover()
  local pos = vim.fn.getmousepos()
  local buf = pos.winid ~= 0 and api.nvim_win_is_valid(pos.winid) and api.nvim_win_get_buf(pos.winid) or nil
  local line = buf and hover_handlers[buf] and pos.line > 0 and pos.line or nil
  if hovered and (hovered.buf ~= buf or not line) and hover_handlers[hovered.buf] then
    hover_handlers[hovered.buf](nil)
  end
  if not line then
    hovered = nil
    return hide_tooltip()
  end
  local tip = hover_handlers[buf](pos)
  if not hovered or hovered.buf ~= buf or hovered.line ~= line or hovered.tip ~= tip then
    hide_tooltip()
    if tip then
      show_tooltip(tip, pos)
    end
  end
  hovered = { buf = buf, line = line, tip = tip }
end
M._update_hover = update_hover

local MOUSEMOVE = vim.keycode('<MouseMove>')
vim.on_key(function(key, typed)
  if (typed ~= '' and typed or key) == MOUSEMOVE and next(hover_handlers) then
    vim.schedule(update_hover)
  end
end, api.nvim_create_namespace('nice-git-hover'))

-- 'mousemoveevent' can cancel half-typed mappings, so it is on only while a hover view is visible.
local function sync_mousemev()
  local visible = false
  for buf in pairs(hover_handlers) do
    if api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0 then
      visible = true
    end
  end
  if visible and saved_mousemev == nil then
    saved_mousemev = vim.o.mousemoveevent
    vim.o.mousemoveevent = true
  elseif not visible and saved_mousemev ~= nil then
    vim.o.mousemoveevent = saved_mousemev
    saved_mousemev = nil
  end
end

---Calls `fn(pos)` whenever the mouse moves over `buf`, and `fn(nil)` when it leaves. `fn` may
---return a tooltip for what is under the mouse.
function M.on_hover(buf, fn)
  hover_handlers[buf] = fn
  local group = api.nvim_create_augroup('NiceGitHover' .. buf, {})
  api.nvim_create_autocmd({ 'BufWinEnter', 'BufWinLeave' }, {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(sync_mousemev)
    end,
  })
  api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    callback = function()
      hover_handlers[buf] = nil
      vim.schedule(sync_mousemev)
    end,
  })
  vim.schedule(sync_mousemev)
end

-- Click / drag ------------------------------------------------------------------------------

---Mouse handling for a list-like buffer. Clicks fire on release (so a click from another window
---works in one go and a press can become a drag). Handlers, all optional except `click`:
---  click(pos)              a press and release without dragging
---  draggable(pos) -> any   payload when a drag may start here
---  dragging(payload, pos)  while dragging (payload nil once it ends), for drop-target feedback
---  drop(payload, pos)      released after dragging
---  right_click(pos)
function M.clickable(buf, h)
  -- { payload, moved } during a drag; false after a press in this buffer; nil when the press
  -- happened in another window (buffer mappings only fire once this buffer has focus).
  local drag

  local function in_buf(pos)
    return pos.winid ~= 0 and api.nvim_win_is_valid(pos.winid) and api.nvim_win_get_buf(pos.winid) == buf and pos.line > 0
  end

  local function on_mouse()
    hide_tooltip()
    local pos = vim.fn.getmousepos()
    local inside = in_buf(pos) and pos.wincol <= api.nvim_win_get_width(pos.winid) -- not the separator
    local payload = inside and h.draggable and h.draggable(pos)
    drag = payload and { payload = payload, moved = false } or false
    return '<LeftMouse>'
  end

  local function on_drag()
    if drag == nil and h.draggable then
      -- The default click already moved the cursor onto the pressed row.
      local win = api.nvim_get_current_win()
      local cur = api.nvim_win_get_cursor(win)
      local payload = h.draggable({ winid = win, line = cur[1], column = cur[2] + 1, wincol = 1 })
      drag = payload and { payload = payload, moved = false } or false
    end
    if not drag then
      return '<LeftDrag>' -- e.g. resizing the window separator
    end
    drag.moved = true
    local pos = vim.fn.getmousepos()
    if h.dragging then
      vim.schedule(function()
        if drag then
          h.dragging(drag.payload, pos)
        end
      end)
    end
    return ''
  end

  local function on_release()
    local mode = vim.fn.mode()
    if mode == 'i' then
      vim.cmd.stopinsert()
    elseif mode:match('^[vV\22]') then
      -- A quick click after a click elsewhere counts as a double-click, whose default (select a
      -- word) already started Visual mode in this buffer.
      vim.cmd('normal! ' .. vim.keycode('<Esc>'))
    end
    local pos = vim.fn.getmousepos()
    local d = drag
    drag = nil
    if h.dragging then
      h.dragging(nil, pos)
    end
    if not in_buf(pos) then
      return
    end
    if d and d.moved then
      if h.drop then
        h.drop(d.payload, pos)
      end
      return
    end
    h.click(pos)
  end

  local function map(modes, lhs, fn, expr)
    vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true, silent = true, expr = expr })
  end
  -- Quick repeated clicks arrive as <2-LeftMouse> etc.; each should act like a single click.
  for _, n in ipairs({ '', '2-', '3-', '4-' }) do
    map('n', '<' .. n .. 'LeftMouse>', on_mouse, true)
    map('n', '<' .. n .. 'LeftDrag>', on_drag, true)
    map({ 'n', 'i', 'x' }, '<' .. n .. 'LeftRelease>', on_release)
  end
  if h.right_click then
    map('n', '<RightMouse>', function()
      local pos = vim.fn.getmousepos()
      if in_buf(pos) then
        api.nvim_set_current_win(pos.winid)
        api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })
        h.right_click(pos)
      end
    end)
  end
  require('nice-git.diff').map_wheel(buf)
end

-- Menus --------------------------------------------------------------------------------------

-- Where the last mouse event happened, so menus open under the pointer.
local function anchor(width, height)
  local pos = vim.fn.getmousepos()
  local row, col
  if pos.screenrow > 0 then
    row, col = pos.screenrow, pos.screencol - 1
  else
    local p = vim.fn.screenpos(0, vim.fn.line('.'), vim.fn.col('.'))
    row, col = p.row, p.col - 1
  end
  row = math.min(row, vim.o.lines - height - 4)
  col = math.min(col, vim.o.columns - width - 2)
  return math.max(row, 0), math.max(col, 0)
end

---Drop-in for vim.ui.select: a bordered menu at the mouse (or cursor). `opts.icon(item)` adds icons.
function M.select(items, opts, on_choice)
  if native() then
    return vim.ui.select(items, opts, on_choice)
  end
  opts = opts or {}
  local format = opts.format_item or tostring
  local lines = {}
  local width = api.nvim_strwidth(opts.prompt or '') + 4
  for i, item in ipairs(items) do
    local icon = opts.icon and opts.icon(item) or ' '
    lines[i] = '  ' .. icon .. '  ' .. format(item) .. '  '
    width = math.max(width, api.nvim_strwidth(lines[i]))
  end
  width = math.min(width, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 6)
  local buf = scratch_buf(lines)
  vim.bo[buf].modifiable = false
  local row, col = anchor(width, height)
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    border = 'rounded',
    style = 'minimal',
    title = opts.prompt and (' ' .. opts.prompt .. ' ') or nil,
    title_pos = opts.prompt and 'left' or nil,
    zindex = 220,
  })
  theme.style_window(win, 'float')
  vim.wo[win].cursorline = true

  local done = false
  local function finish(idx)
    if done then
      return
    end
    done = true
    close_win(win)
    on_choice(idx and items[idx] or nil, idx)
  end
  local function key(lhs, fn)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  key('<CR>', function()
    finish(api.nvim_win_get_cursor(win)[1])
  end)
  for _, lhs in ipairs({ '<Esc>', 'q' }) do
    key(lhs, function()
      finish(nil)
    end)
  end
  M.clickable(buf, {
    click = function(pos)
      finish(pos.line)
    end,
  })
  M.on_hover(buf, function(pos)
    if pos and api.nvim_win_is_valid(win) then
      api.nvim_win_set_cursor(win, { pos.line, 0 })
    end
  end)
  api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        finish(nil)
      end)
    end,
  })
end

---Drop-in for vim.ui.input: a one-line bordered box. <CR> confirms, <Esc> cancels.
function M.input(opts, on_confirm)
  if native() then
    return vim.ui.input(opts, on_confirm)
  end
  opts = opts or {}
  local width = math.min(math.max(50, api.nvim_strwidth(opts.default or '') + 4), vim.o.columns - 6)
  local buf = scratch_buf({ opts.default or '' })
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.floor(vim.o.lines * 0.3),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = 1,
    border = 'rounded',
    style = 'minimal',
    title = ' ' .. vim.trim(opts.prompt or 'Input'):gsub(':$', '') .. ' ',
    title_pos = 'left',
    footer = ' Enter to confirm · Esc to cancel ',
    footer_pos = 'right',
    zindex = 220,
  })
  theme.style_window(win, 'input')
  vim.cmd.startinsert({ bang = true })

  local done = false
  local function finish(value)
    if done then
      return
    end
    done = true
    vim.cmd.stopinsert()
    close_win(win)
    vim.schedule(function()
      on_confirm(value)
    end)
  end
  vim.keymap.set({ 'n', 'i' }, '<CR>', function()
    finish(api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  end, { buffer = buf })
  vim.keymap.set({ 'n', 'i' }, '<Esc>', function()
    finish(nil)
  end, { buffer = buf })
  api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      finish(nil)
    end,
  })
end

return M
