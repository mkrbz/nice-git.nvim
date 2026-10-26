local api = vim.api
local git = require('nice-git.git')

local M = {}

M.config = {
  width = 40,
  position = 'right', -- or 'left'
  debounce = 100,
  diff_mode = 'split', -- or 'inline'
  repaint_after_scroll = true, -- repaint once after side-by-side panes scroll (fixes stale strips in some terminals)
  native_ui = false, -- true: use vim.notify / vim.ui.select / vim.ui.input instead of nice-git's floats
  icons = {}, -- override any icon in lua/nice-git/theme.lua
}

---Shared state: repo paths and the last parsed status.
M.state = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  local theme = require('nice-git.theme')
  theme.icons = vim.tbl_extend('force', theme.icons, M.config.icons or {})
end

local watchers = {}
local timer = assert(vim.uv.new_timer())
local busy, again = false, false

-- The multi-step operation in progress, judged by the state files git leaves in the git dir.
local function operation(gitdir)
  local function exists(name)
    return vim.uv.fs_stat(gitdir .. '/' .. name) ~= nil
  end
  if exists('rebase-merge') or exists('rebase-apply') then
    return 'rebase'
  elseif exists('MERGE_HEAD') then
    return 'merge'
  elseif exists('CHERRY_PICK_HEAD') then
    return 'cherry-pick'
  elseif exists('REVERT_HEAD') then
    return 'revert'
  end
end

function M.refresh()
  if not M.state.root then
    return
  end
  if busy then
    again = true
    return
  end
  busy = true
  local root = M.state.root
  local function done()
    busy = false
    if again then
      again = false
      M.refresh()
    end
  end
  git.status(root, function(status, err)
    if not status then
      require('nice-git.ui').notify(err, vim.log.levels.ERROR)
      return done()
    end
    status.operation = operation(M.state.gitdir)
    -- The rest of the panel's data, fetched in parallel; each result lands on `status`.
    local extras = { stashes = git.stashes, worktrees = git.worktrees, submodules = git.submodules, superproject = git.superproject }
    local pending = vim.tbl_count(extras)
    for key, fetch in pairs(extras) do
      fetch(root, function(result)
        status[key] = result
        pending = pending - 1
        if pending > 0 then
          return
        end
        if root == M.state.root then
          M.state.status = status
          require('nice-git.sidebar').render()
          require('nice-git.diff').refresh()
          local log = require('nice-git.log')
          if log.buf and #vim.fn.win_findbuf(log.buf) > 0 then
            log.refresh()
          end
        end
        done()
      end)
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

---Finds the repository of `dir` (default: the current file, or cwd), makes it the active one,
---then calls cb.
function M.with_root(cb, dir)
  local file = api.nvim_buf_get_name(0)
  dir = dir or vim.bo.buftype == '' and file ~= '' and vim.fs.dirname(file) or vim.fn.getcwd()
  git.resolve(dir, function(root, gitdir, err)
    if not root then
      return require('nice-git.ui').notify(err, vim.log.levels.WARN)
    end
    if root ~= M.state.root then
      M.unwatch()
      M.state = { root = root, gitdir = gitdir }
    end
    cb()
  end)
end

function M.open(dir)
  M.with_root(function()
    require('nice-git.sidebar').open_win()
    M.watch()
    M.refresh()
  end, dir)
end

---Makes another repository (a worktree or submodule) the active one for this tab.
function M.switch_repo(path)
  vim.cmd.tcd(vim.fn.fnameescape(path))
  M.open(path)
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
