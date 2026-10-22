local api = vim.api
local git = require('nice-git.git')

local M = {}

M.config = {
  width = 35,
  debounce = 100,
  diff_mode = 'split', -- or 'inline'
}

---Shared state: repo paths and the last parsed status.
M.state = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

local watchers = {}
local timer = assert(vim.uv.new_timer())
local busy, again = false, false

function M.refresh()
  if not M.state.root then
    return
  end
  if busy then
    again = true
    return
  end
  busy = true
  git.status(M.state.root, function(status, err)
    busy = false
    if status then
      M.state.status = status
      require('nice-git.sidebar').render()
      require('nice-git.diff').refresh()
    else
      vim.notify('nice-git: ' .. err, vim.log.levels.ERROR)
    end
    if again then
      again = false
      M.refresh()
    end
  end)
end

---Debounced refresh; bursts of file events collapse into one `git status`.
function M.schedule_refresh()
  if #watchers == 0 then
    return
  end
  timer:stop()
  timer:start(M.config.debounce, 0, vim.schedule_wrap(M.refresh))
end

function M.unwatch()
  for _, w in ipairs(watchers) do
    w:close()
  end
  watchers = {}
end

-- Watches .git (index, HEAD) and the top level of the worktree. Linux inotify isn't recursive,
-- so edits in subdirectories are picked up by BufWritePost/FocusGained instead.
function M.watch()
  local root, gitdir = M.state.root, M.state.gitdir
  if not root or (#watchers > 0 and M.state.watched == root) then
    return
  end
  M.unwatch()
  M.state.watched = root
  for _, dir in ipairs({ gitdir, root }) do
    local w = assert(vim.uv.new_fs_event())
    w:start(dir, {}, function(_, fname)
      if fname ~= '.git' and not (fname or ''):match('%.lock$') then
        vim.schedule(M.schedule_refresh)
      end
    end)
    table.insert(watchers, w)
  end
end

function M.open()
  local file = api.nvim_buf_get_name(0)
  local dir = vim.bo.buftype == '' and file ~= '' and vim.fs.dirname(file) or vim.fn.getcwd()
  git.resolve(dir, function(root, gitdir, err)
    if not root then
      return vim.notify('nice-git: ' .. err, vim.log.levels.WARN)
    end
    if root ~= M.state.root then
      M.unwatch()
      M.state = { root = root, gitdir = gitdir }
    end
    require('nice-git.sidebar').open_win()
    M.refresh()
  end)
end

function M.toggle()
  local sidebar = require('nice-git.sidebar')
  if sidebar.win_in_tab() then
    sidebar.close()
  else
    M.open()
  end
end

local group = api.nvim_create_augroup('NiceGit', {})
api.nvim_create_autocmd({ 'BufWritePost', 'FocusGained' }, { group = group, callback = M.schedule_refresh })

return M
