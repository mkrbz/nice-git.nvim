-- Conflict markers in a working file: highlights, clickable "Accept …" buttons, resolve keys.
local api = vim.api

local M = {}

local ns = api.nvim_create_namespace('nice-git-conflict')
local group = api.nvim_create_augroup('NiceGitConflict', {})

-- Buttons drawn over each `<<<<<<<` line, in order; `col` ranges are filled in below.
local BUTTONS = {
  { label = ' Accept Current ', pick = 'ours' },
  { label = ' Accept Incoming ', pick = 'theirs' },
  { label = ' Accept Both ', pick = 'both' },
}
do
  local col = 0
  for i, b in ipairs(BUTTONS) do
    b.from = col
    col = col + api.nvim_strwidth(b.label) + (i < #BUTTONS and 1 or 0) -- '│' separator
    b.to = col
  end
end

local KEYS = { co = 'ours', ct = 'theirs', cb = 'both', c0 = 'none' }

---Conflicts as { start, base?, mid, finish } line numbers (1-based, marker lines included).
function M.parse(lines)
  local out, c = {}, nil
  for i, l in ipairs(lines) do
    if l:match('^<<<<<<<') then
      c = { start = i }
    elseif c and not c.mid and l:match('^|||||||') then
      c.base = i
    elseif c and not c.mid and l:match('^=======') then
      c.mid = i
    elseif c and c.mid and l:match('^>>>>>>>') then
      c.finish = i
      table.insert(out, c)
      c = nil
    end
  end
  return out
end

local function conflicts()
  return M.parse(api.nvim_buf_get_lines(M.buf, 0, -1, false))
end

local function decorate()
  local buf = M.buf
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return
  end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local function hl(from, to, group_name)
    for l = from, to do
      api.nvim_buf_set_extmark(buf, ns, l - 1, 0, { line_hl_group = group_name })
    end
  end
  for _, c in ipairs(conflicts()) do
    local virt = {}
    for i, b in ipairs(BUTTONS) do
      table.insert(virt, { b.label, 'NiceGitConflictButton' })
      if i < #BUTTONS then
        table.insert(virt, { '│', 'NiceGitConflictMarker' })
      end
    end
    api.nvim_buf_set_extmark(buf, ns, c.start - 1, 0, { virt_text = virt, virt_text_pos = 'overlay' })
    hl(c.start, c.start, 'NiceGitConflictMarker')
    hl(c.start + 1, (c.base or c.mid) - 1, 'NiceGitConflictOurs')
    if c.base then
      hl(c.base, c.mid - 1, 'NiceGitConflictBase')
    end
    hl(c.mid, c.mid, 'NiceGitConflictMarker')
    hl(c.mid + 1, c.finish - 1, 'NiceGitConflictTheirs')
    hl(c.finish, c.finish, 'NiceGitConflictMarker')
    api.nvim_buf_set_extmark(buf, ns, c.mid - 1, 0, {
      virt_text = { { ' ↑ current  ↓ incoming', 'NiceGitConflictMarker' } },
      virt_text_pos = 'eol',
    })
  end
end

---Replaces conflict `c` with the chosen side(s).
function M.resolve(c, pick)
  local lines = api.nvim_buf_get_lines(M.buf, c.start - 1, c.finish, false)
  local function region(from, to)
    return vim.list_slice(lines, from - c.start + 1, to - c.start + 1)
  end
  local ours = region(c.start + 1, (c.base or c.mid) - 1)
  local theirs = region(c.mid + 1, c.finish - 1)
  local keep = ({ ours = ours, theirs = theirs, both = vim.list_extend(vim.list_extend({}, ours), theirs), none = {} })[pick]
  api.nvim_buf_set_lines(M.buf, c.start - 1, c.finish, false, keep)
end

local function at_cursor()
  local line = api.nvim_win_get_cursor(0)[1]
  for _, c in ipairs(conflicts()) do
    if line >= c.start and line <= c.finish then
      return c
    end
  end
  vim.notify('nice-git: no conflict under the cursor', vim.log.levels.WARN)
end

function M.resolve_all(pick)
  -- Bottom-up so earlier line numbers stay valid.
  local list = conflicts()
  for i = #list, 1, -1 do
    M.resolve(list[i], pick)
  end
end

function M.count()
  return M.buf and api.nvim_buf_is_valid(M.buf) and #conflicts() or 0
end

function M.jump(dir)
  local list = conflicts()
  if #list == 0 then
    return
  end
  local line = api.nvim_win_get_cursor(0)[1]
  local target = dir > 0 and list[1] or list[#list]
  for i = 1, #list do
    local c = dir > 0 and list[i] or list[#list + 1 - i]
    if (dir > 0 and c.start > line) or (dir < 0 and c.start < line) then
      target = c
      break
    end
  end
  api.nvim_win_set_cursor(0, { target.start, 0 })
  vim.cmd('normal! zz')
end

-- A click on a `<<<<<<<` line hits one of the overlaid buttons; anything else is a normal click.
local function on_release()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or api.nvim_win_get_buf(pos.winid) ~= M.buf then
    return '<LeftRelease>'
  end
  local info = vim.fn.getwininfo(pos.winid)[1]
  local leftcol = api.nvim_win_call(pos.winid, vim.fn.winsaveview).leftcol
  local col = pos.wincol - 1 - info.textoff + leftcol
  for _, c in ipairs(conflicts()) do
    if c.start == pos.line then
      for _, b in ipairs(BUTTONS) do
        if col >= b.from and col < b.to then
          vim.schedule(function()
            M.resolve(c, b.pick)
          end)
          return ''
        end
      end
    end
  end
  return '<LeftRelease>'
end

function M.attach(buf)
  M.detach()
  M.buf = buf
  for lhs, pick in pairs(KEYS) do
    vim.keymap.set('n', lhs, function()
      local c = at_cursor()
      if c then
        M.resolve(c, pick)
      end
    end, { buffer = buf, desc = 'nice-git: accept ' .. pick })
  end
  vim.keymap.set('n', '<LeftRelease>', on_release, { buffer = buf, expr = true })
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, { group = group, buffer = buf, callback = decorate })
  decorate()
end

function M.detach()
  local buf = M.buf
  M.buf = nil
  api.nvim_clear_autocmds({ group = group })
  if buf and api.nvim_buf_is_valid(buf) then
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for lhs in pairs(KEYS) do
      pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
    end
    pcall(vim.keymap.del, 'n', '<LeftRelease>', { buffer = buf })
  end
end

return M
