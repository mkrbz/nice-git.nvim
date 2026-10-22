-- Interactive rebase planner: a float listing commits oldest first. Drag rows to reorder,
-- click the action badge to cycle it, then Start.
local api = vim.api
local git = require('nice-git.git')

local M = {}

local ns = api.nvim_create_namespace('nice-git-rebase')
local ns_drop = api.nvim_create_namespace('nice-git-rebase-drop')

local ACTIONS = { 'pick', 'reword', 'edit', 'squash', 'fixup', 'drop' }
local ACTION_HL = {
  pick = 'NiceGitButton',
  reword = 'NiceGitModified',
  edit = 'NiceGitModified',
  squash = 'NiceGitRef',
  fixup = 'NiceGitRef',
  drop = 'NiceGitDeleted',
}
local KEYS = { p = 'pick', r = 'reword', e = 'edit', s = 'squash', f = 'fixup', d = 'drop' }

-- Byte columns (0-based, end exclusive) of the badge in each commit line: "  [pick  ] ..."
local BADGE = { 2, 10 }
local START, CANCEL = '▶ Start rebase', '✕ Cancel'

local plan -- { base, root, buf, win, commits = { {hash, subject, action, message?} } }

local function state()
  return require('nice-git').state
end

local function render()
  local lines = {}
  for _, c in ipairs(plan.commits) do
    local subject = c.message and ('✎ ' .. c.message) or c.subject
    table.insert(lines, ('  [%-6s] %s %s'):format(c.action, c.hash, subject))
  end
  table.insert(lines, '')
  table.insert(lines, '  ' .. START .. '    ' .. CANCEL)
  local buf = plan.buf
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, c in ipairs(plan.commits) do
    api.nvim_buf_set_extmark(buf, ns, i - 1, BADGE[1], { end_col = BADGE[2], hl_group = ACTION_HL[c.action] })
    api.nvim_buf_set_extmark(buf, ns, i - 1, BADGE[2] + 1, { end_col = BADGE[2] + 1 + #c.hash, hl_group = 'NiceGitHash' })
    if c.action == 'drop' then
      api.nvim_buf_set_extmark(buf, ns, i - 1, BADGE[2] + 1, { end_col = #lines[i], hl_group = 'NiceGitPath' })
    end
  end
  local last = #lines - 1
  api.nvim_buf_set_extmark(buf, ns, last, 2, { end_col = 2 + #START, hl_group = 'NiceGitCommitButton' })
  api.nvim_buf_set_extmark(buf, ns, last, 6 + #START, { end_col = #lines[#lines], hl_group = 'NiceGitButton' })
end

---@param on_cancel? fun() runs when a reword prompt is dismissed
local function set_action(i, action, on_cancel)
  local c = plan.commits[i]
  if not c then
    return
  end
  if action ~= 'reword' then
    c.action, c.message = action, nil
    return render()
  end
  require('nice-git.ui').input({ prompt = 'New message: ', default = c.message or c.subject }, function(msg)
    if msg and vim.trim(msg) ~= '' then
      c.action, c.message = 'reword', vim.trim(msg)
      render()
    elseif on_cancel then
      on_cancel()
    end
  end)
end

local function cycle(i)
  local c = plan.commits[i]
  local idx = 1
  for k, a in ipairs(ACTIONS) do
    if a == c.action then
      idx = k
    end
  end
  local next = ACTIONS[idx % #ACTIONS + 1]
  -- Dismissing the reword prompt moves on, so cycling never gets stuck on it.
  set_action(i, next, function()
    set_action(i, ACTIONS[(idx + 1) % #ACTIONS + 1])
  end)
end

local function move(from, to)
  local n = #plan.commits
  if from == to or from < 1 or from > n or to < 1 or to > n then
    return
  end
  table.insert(plan.commits, to, table.remove(plan.commits, from))
  render()
  api.nvim_win_set_cursor(plan.win, { to, 0 })
end

function M.close()
  if plan and api.nvim_win_is_valid(plan.win) then
    api.nvim_win_close(plan.win, true)
  end
  plan = nil
end

local function quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

---The git-rebase-todo for the current plan; rewords become `pick` plus an amending `exec`.
local function todo()
  local lines = {}
  for _, c in ipairs(plan.commits) do
    if c.action == 'reword' then
      table.insert(lines, 'pick ' .. c.hash)
      table.insert(lines, 'exec git commit --amend --only --allow-empty --no-verify -m ' .. quote(c.message))
    else
      table.insert(lines, c.action .. ' ' .. c.hash)
    end
  end
  return table.concat(lines, '\n') .. '\n'
end

function M.start()
  if not plan then
    return
  end
  local first = plan.commits[1]
  if first and (first.action == 'squash' or first.action == 'fixup') then
    return require('nice-git.ui').notify('the first commit has nothing to ' .. first.action .. ' into', vim.log.levels.WARN)
  end
  local args = { 'rebase', '--interactive', '--autostash' }
  table.insert(args, plan.base or '--root')
  -- git runs the sequence editor through the shell with the todo file appended.
  local env = { GIT_SEQUENCE_EDITOR = 'printf "%s" "$NICE_GIT_TODO" >', NICE_GIT_TODO = todo() }
  local root = plan.root
  M.close()
  git.run(root, args, function(ok, out, err)
    if ok then
      require('nice-git.ui').notify('rebase done')
    else
      require('nice-git.ui').notify('rebase stopped: ' .. vim.trim(err ~= '' and err or out), vim.log.levels.WARN)
    end
    vim.cmd.checktime()
    require('nice-git').refresh()
    local log = require('nice-git.log')
    if log.buf and api.nvim_buf_is_valid(log.buf) then
      log.refresh()
    end
  end, { env = env })
end

-- Mouse: press on a commit row and drag to reorder; click the badge or the buttons.
local drag

local function row_at(pos)
  if plan and pos.winid == plan.win and pos.line > 0 then
    return pos.line
  end
end

local function on_mouse()
  local pos = vim.fn.getmousepos()
  local line = row_at(pos)
  drag = line and line <= #plan.commits and { from = line, moved = false } or nil
  return '<LeftMouse>'
end

local function on_drag()
  if not drag then
    return '<LeftDrag>'
  end
  drag.moved = true
  local line = row_at(vim.fn.getmousepos())
  vim.schedule(function()
    if plan then
      api.nvim_buf_clear_namespace(plan.buf, ns_drop, 0, -1)
      if line and line <= #plan.commits then
        api.nvim_buf_set_extmark(plan.buf, ns_drop, line - 1, 0, { line_hl_group = 'NiceGitDropTarget' })
      end
    end
  end)
  return ''
end

local function on_release()
  local pos = vim.fn.getmousepos()
  local d = drag
  drag = nil
  if not plan then
    return
  end
  api.nvim_buf_clear_namespace(plan.buf, ns_drop, 0, -1)
  local line = row_at(pos)
  if not line then
    return
  end
  if d and d.moved then
    return move(d.from, math.min(line, #plan.commits))
  end
  local col = pos.column - 1
  if line <= #plan.commits then
    if col >= BADGE[1] and col < BADGE[2] then
      cycle(line)
    end
  elseif line == #plan.commits + 2 then
    if col >= 2 and col < 2 + #START then
      M.start()
    elseif col >= 6 + #START then
      M.close()
    end
  end
end

local function open_float(base, root, commits)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'nice-git-rebase'
  local width = 60
  for _, c in ipairs(commits) do
    width = math.max(width, 14 + #c.hash + api.nvim_strwidth(c.subject))
  end
  width = math.min(width, vim.o.columns - 6)
  local height = math.min(#commits + 2, vim.o.lines - 6)
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    border = 'rounded',
    title = ' Interactive rebase ',
    title_pos = 'center',
    footer = ' drag to reorder · click an action to change it ',
    footer_pos = 'center',
  })
  require('nice-git.theme').style_window(win, 'float')
  vim.wo[win].cursorline, vim.wo[win].wrap = true, false
  plan = { base = base, root = root, buf = buf, win = win, commits = commits }
  render()

  local function map(lhs, fn, opts)
    vim.keymap.set('n', lhs, fn, vim.tbl_extend('force', { buffer = buf, nowait = true, silent = true }, opts or {}))
  end
  local function cur()
    return api.nvim_win_get_cursor(0)[1]
  end
  for _, n in ipairs({ '', '2-', '3-', '4-' }) do
    map('<' .. n .. 'LeftMouse>', on_mouse, { expr = true })
    map('<' .. n .. 'LeftDrag>', on_drag, { expr = true })
    map('<' .. n .. 'LeftRelease>', on_release)
  end
  for key, action in pairs(KEYS) do
    map(key, function()
      set_action(cur(), action)
    end)
  end
  map('<Tab>', function()
    if cur() <= #plan.commits then
      cycle(cur())
    end
  end)
  map('J', function()
    move(cur(), cur() + 1)
  end)
  map('K', function()
    move(cur(), cur() - 1)
  end)
  map('<CR>', M.start)
  map('q', M.close)
  map('<Esc>', M.close)
end

---Plans an interactive rebase of `hash` and every commit after it on the current branch.
function M.open(hash)
  local root = state().root
  git.run(root, { 'rev-parse', '--verify', '-q', hash .. '^' }, function(has_parent)
    local base = has_parent and hash .. '^' or nil
    local args = { 'log', '--reverse', '--no-merges', '--format=%h%x00%s', base and base .. '..HEAD' or 'HEAD' }
    git.run(root, args, function(ok, out, err)
      if not ok then
        return require('nice-git.ui').notify(vim.trim(err), vim.log.levels.ERROR)
      end
      local commits = {}
      for _, line in ipairs(vim.split(out, '\n', { trimempty = true })) do
        local h, subject = unpack(vim.split(line, '\0', { plain = true }))
        table.insert(commits, { hash = h, subject = subject, action = 'pick' })
      end
      if #commits == 0 then
        return require('nice-git.ui').notify('no commits to rebase (is that commit on this branch?)', vim.log.levels.WARN)
      end
      open_float(base, root, commits)
    end)
  end)
end

return M
