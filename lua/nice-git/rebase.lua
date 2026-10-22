-- Interactive rebase planner: a float listing commits oldest first. Drag rows to reorder,
-- click the action badge to cycle it, then Start.
local api = vim.api
local git = require('nice-git.git')
local theme = require('nice-git.theme')
local ui = require('nice-git.ui')

local M = {}

local ns = api.nvim_create_namespace('nice-git-rebase')
local ns_drop = api.nvim_create_namespace('nice-git-rebase-drop')

local ACTIONS = { 'pick', 'reword', 'edit', 'squash', 'fixup', 'drop' }
-- Actions that change a commit stand out; pick (and drop, whose row is struck through) stay quiet.
local ACTION_HL = {
  pick = 'NiceGitPillSoft',
  reword = 'NiceGitPill',
  edit = 'NiceGitPill',
  squash = 'NiceGitPill',
  fixup = 'NiceGitPill',
  drop = 'NiceGitPillSoft',
}
local KEYS = { p = 'pick', r = 'reword', e = 'edit', s = 'squash', f = 'fixup', d = 'drop' }

local plan -- { base, root, buf, win, commits = { {hash, subject, action, message?} } }

local function state()
  return require('nice-git').state
end

local function pill(text, hls, label, body)
  local i = theme.icons
  for _, part in ipairs({ { i.pill_left, body .. 'Edge' }, { ' ' .. label .. ' ', body }, { i.pill_right, body .. 'Edge' } }) do
    local start = #text
    text = text .. part[1]
    table.insert(hls, { start, #text, part[2] })
  end
  return text
end

-- Draws the plan; plan.rows[n] keeps each line's clickable byte ranges.
local function render()
  local icons = theme.icons
  local lines, all_hls = {}, {}
  plan.rows = {}
  for n, c in ipairs(plan.commits) do
    local hls = {}
    local text = '  ' .. icons.gripper
    table.insert(hls, { 2, #text, 'NiceGitDim' })
    text = text .. '  '
    local b0 = #text
    text = pill(text, hls, ('%-6s'):format(c.action), ACTION_HL[c.action])
    local b1 = #text
    text = text .. '  '
    local s0 = #text
    text = text .. c.hash
    table.insert(hls, { s0, #text, 'NiceGitAccent' })
    text = text .. '  '
    s0 = #text
    text = text .. (c.message and (icons.edit .. ' ' .. c.message) or c.subject)
    if c.action == 'drop' then
      table.insert(hls, { s0, #text, 'NiceGitDeleted' })
    end
    lines[n], all_hls[n] = text, hls
    plan.rows[n] = { badge = { b0, b1 } }
  end
  table.insert(lines, '')
  local hls = {}
  local text = '  '
  local s0 = #text
  text = pill(text, hls, icons.check .. ' Start Rebase', 'NiceGitPill')
  plan.start_btn = { s0, #text }
  text = text .. '   '
  s0 = #text
  text = pill(text, hls, 'Cancel', 'NiceGitPillSoft')
  plan.cancel_btn = { s0, #text }
  table.insert(lines, text)
  all_hls[#lines] = hls

  local buf = plan.buf
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for l, list in pairs(all_hls) do
    for _, h in ipairs(list) do
      api.nvim_buf_set_extmark(buf, ns, l - 1, h[1], { end_col = h[2], hl_group = h[3] })
    end
  end
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

-- Mouse: drag a commit row to reorder it; click its action pill or the buttons below.
local function within(range, pos)
  return range and pos.column > range[1] and pos.column <= range[2]
end

local function click(pos)
  local line = pos.line
  if line <= #plan.commits then
    if within(plan.rows[line].badge, pos) then
      cycle(line)
    end
  elseif line == #plan.commits + 2 then
    if within(plan.start_btn, pos) then
      M.start()
    elseif within(plan.cancel_btn, pos) then
      M.close()
    end
  end
end

local function show_drop_target(from, pos)
  if not plan then
    return
  end
  api.nvim_buf_clear_namespace(plan.buf, ns_drop, 0, -1)
  if from and pos.line >= 1 and pos.line <= #plan.commits then
    api.nvim_buf_set_extmark(plan.buf, ns_drop, pos.line - 1, 0, { line_hl_group = 'NiceGitDropTarget' })
  end
end

local function open_float(base, root, commits)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'nice-git-rebase'
  local width = 60
  for _, c in ipairs(commits) do
    width = math.max(width, 22 + #c.hash + api.nvim_strwidth(c.subject))
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
    title = ' ' .. theme.icons.edit .. ' Interactive Rebase ',
    title_pos = 'center',
    footer = ' drag rows to reorder · click an action to change it ',
    footer_pos = 'center',
  })
  theme.style_window(win, 'float')
  vim.wo[win].cursorline, vim.wo[win].wrap = true, false
  plan = { base = base, root = root, buf = buf, win = win, commits = commits }
  render()

  local function map(lhs, fn, opts)
    vim.keymap.set('n', lhs, fn, vim.tbl_extend('force', { buffer = buf, nowait = true, silent = true }, opts or {}))
  end
  local function cur()
    return api.nvim_win_get_cursor(0)[1]
  end
  ui.clickable(buf, {
    click = click,
    draggable = function(pos)
      return pos.line <= #plan.commits and pos.line or nil
    end,
    dragging = show_drop_target,
    drop = function(from, pos)
      move(from, math.max(1, math.min(pos.line, #plan.commits)))
    end,
  })
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
    local args = { 'log', '--reverse', '--topo-order', '--no-merges', '--format=%h%x00%s', base and base .. '..HEAD' or 'HEAD' }
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
