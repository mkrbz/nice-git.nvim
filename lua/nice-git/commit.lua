-- Commit message box shown above the file list.
local api = vim.api
local git = require('nice-git.git')

local M = { amend = false }

local ns = api.nvim_create_namespace('nice-git-commit')

local function state()
  return require('nice-git').state
end

local function message()
  local lines = api.nvim_buf_get_lines(M.buf, 0, -1, false)
  while #lines > 0 and vim.trim(lines[#lines]) == '' do
    table.remove(lines)
  end
  return table.concat(lines, '\n')
end

local function set_message(text)
  api.nvim_buf_set_lines(M.buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
end

function M.update_placeholder()
  local buf = M.buf
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return
  end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if api.nvim_buf_line_count(buf) == 1 and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == '' then
    local status = state().status or {}
    local text = M.amend and 'Message (empty keeps the previous one)'
      or status.operation == 'merge' and 'Message (empty uses the merge message)'
      or 'Message (Ctrl-Enter to commit)'
    api.nvim_buf_set_extmark(buf, ns, 0, 0, { virt_text = { { text, 'NiceGitPlaceholder' } }, virt_text_pos = 'overlay' })
  end
end

local function ensure_buf()
  if M.buf and api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, 'nice-git://commit')
  vim.bo[buf].filetype = 'gitcommit'
  M.buf = buf
  for _, lhs in ipairs({ '<C-CR>', '<C-s>' }) do
    vim.keymap.set({ 'n', 'i' }, lhs, M.commit, { buffer = buf, desc = 'Commit' })
  end
  require('nice-git.diff').map_wheel(buf)
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWinEnter' }, {
    buffer = buf,
    callback = M.update_placeholder,
  })
  return buf
end

function M.win_in_tab()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(w) == M.buf then
      return w
    end
  end
end

---Opens the box above the panel's file list window.
function M.open_win(list_win)
  local buf = ensure_buf()
  if M.win_in_tab() then
    return
  end
  local win = api.nvim_open_win(buf, false, { split = 'above', win = list_win, height = 3 })
  local wo = vim.wo[win]
  wo.number, wo.relativenumber, wo.list = false, false, false
  wo.signcolumn, wo.foldcolumn, wo.statuscolumn = 'no', '0', ''
  wo.wrap, wo.winfixheight, wo.winfixbuf = true, true, true
  M.update_placeholder()
end

function M.focus()
  local win = M.win_in_tab()
  if win then
    api.nvim_set_current_win(win)
    vim.cmd.startinsert({ bang = true })
  end
end

local function rerender()
  require('nice-git.sidebar').render()
  M.update_placeholder()
end

function M.toggle_amend()
  M.amend = not M.amend
  local st = state()
  if M.amend and message() == '' and st.status and st.status.has_head then
    git.run(st.root, { 'log', '-1', '--format=%B' }, function(ok, out)
      if ok and M.amend and message() == '' then
        set_message(vim.trim(out))
      end
      rerender()
    end)
  end
  rerender()
end

function M.commit()
  local st = state()
  local status = st.status
  if not (st.root and status and M.buf) then
    return
  end
  local msg = message()
  -- Concluding a merge may reuse git's prepared message.
  local merging = status.operation == 'merge'
  if msg == '' and not M.amend and not merging then
    return vim.notify('nice-git: enter a commit message first', vim.log.levels.WARN)
  end
  local args = { 'commit' }
  if M.amend then
    table.insert(args, '--amend')
  elseif #status.staged == 0 and not merging then
    if #status.changes == 0 then
      return vim.notify('nice-git: nothing to commit', vim.log.levels.WARN)
    end
    if vim.fn.confirm('No staged changes. Stage all tracked changes and commit?', '&Yes\n&No', 1) ~= 1 then
      return
    end
    table.insert(args, '--all')
  end
  vim.list_extend(args, msg == '' and { '--no-edit' } or { '--file=-' })
  git.run(st.root, args, function(ok, out, err)
    if not ok then
      return vim.notify('nice-git: ' .. vim.trim(err ~= '' and err or out), vim.log.levels.ERROR)
    end
    set_message('')
    M.amend = false
    vim.cmd.stopinsert()
    vim.notify('nice-git: ' .. vim.split(vim.trim(out), '\n', { plain = true })[1])
    require('nice-git').refresh()
  end, { stdin = msg ~= '' and msg or nil })
end

return M
