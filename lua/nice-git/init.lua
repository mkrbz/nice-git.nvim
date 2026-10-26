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

-- What hide_workspace() put away: { panel_tabs, view, log, focus }.
local hidden

---Whether any part of nice-git is on screen: the panel in some tab, the diff tab or the graph.
local function workspace_visible()
  local sidebar = require('nice-git.sidebar')
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    if sidebar.buf and sidebar.visible_in(tab) then
      return true
    end
  end
  return require('nice-git.diff').tab() ~= nil or require('nice-git.log').tab() ~= nil
end

---Closes every nice-git window (panel, diff tab, graph tab) and remembers them for show_workspace().
function M.hide_workspace()
  local sidebar, diff, log = require('nice-git.sidebar'), require('nice-git.diff'), require('nice-git.log')
  local current = api.nvim_get_current_tabpage()
  local view_tab, log_tab = diff.tab(), log.tab()
  hidden = { panel_tabs = {}, view = diff.snapshot(), log = log.snapshot(), focus = current }
  if current == view_tab then
    hidden.focus = 'view'
  elseif current == log_tab then
    hidden.focus = 'log'
  end
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    if tab ~= view_tab and tab ~= log_tab and sidebar.buf and sidebar.visible_in(tab) then
      table.insert(hidden.panel_tabs, tab)
      sidebar.close_in(tab)
    end
  end
  log.close()
  diff.close_tab()
  -- Land in the tab you were working in (or the one you were in before the nice-git tabs).
  if type(hidden.focus) ~= 'string' and api.nvim_tabpage_is_valid(hidden.focus) then
    api.nvim_set_current_tabpage(hidden.focus)
  end
end

---Brings back everything hide_workspace() put away, as it was.
function M.show_workspace()
  local h = hidden
  hidden = nil
  if not h then
    return M.open()
  end
  local origin = api.nvim_get_current_tabpage()
  local function finish()
    if h.focus == 'log' and require('nice-git.log').tab() then
      api.nvim_set_current_tabpage(require('nice-git.log').tab())
    elseif h.focus == 'view' and require('nice-git.diff').tab() then
      api.nvim_set_current_tabpage(require('nice-git.diff').tab())
    elseif type(h.focus) ~= 'string' and api.nvim_tabpage_is_valid(h.focus) then
      api.nvim_set_current_tabpage(h.focus)
    elseif api.nvim_tabpage_is_valid(origin) then
      api.nvim_set_current_tabpage(origin)
    end
  end
  M.with_root(function()
    local sidebar = require('nice-git.sidebar')
    for _, tab in ipairs(h.panel_tabs) do
      if api.nvim_tabpage_is_valid(tab) then
        api.nvim_set_current_tabpage(tab)
        sidebar.open_win()
      end
    end
    if h.log then
      require('nice-git.log').show(h.log.cursor)
    end
    if h.view then
      require('nice-git.diff').restore(h.view, finish)
    else
      finish()
    end
    M.refresh()
  end)
end

---One switch for the whole workspace: hide it if any part is showing, otherwise bring it back.
function M.toggle_workspace()
  if workspace_visible() then
    M.hide_workspace()
  else
    M.show_workspace()
  end
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
