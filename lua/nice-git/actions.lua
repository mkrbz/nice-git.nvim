-- Repo-level commands triggered from the panel: sync with remotes and branch switching.
local git = require('nice-git.git')

local M = {}

local function state()
  return require('nice-git').state
end

local function notify(msg, level)
  require('nice-git.ui').notify(msg, level)
end

---Runs a git command that changes the repo, then reloads open buffers and the panel.
---@param on_ok? fun(out: string)
function M.run(args, on_ok, opts)
  git.run(state().root, args, function(ok, out, err)
    if not ok then
      notify(vim.trim(err ~= '' and err or out), vim.log.levels.ERROR)
    elseif on_ok then
      on_ok(out)
    end
    vim.cmd.checktime()
    require('nice-git').refresh()
  end, opts)
end

-- Name of the remote operation in progress, shown in the panel header.
M.busy = nil

local function remote(name, args)
  if M.busy then
    return notify('wait for ' .. M.busy .. ' to finish', vim.log.levels.WARN)
  end
  M.busy = name
  require('nice-git.sidebar').render()
  git.run(state().root, args, function(ok, out, err)
    M.busy = nil
    if ok then
      notify(name .. ' done')
    else
      notify(name .. ' failed: ' .. vim.trim(err ~= '' and err or out), vim.log.levels.ERROR)
    end
    vim.cmd.checktime()
    require('nice-git').refresh()
  end)
end

function M.fetch()
  remote('fetch', { 'fetch', '--all', '--prune' })
end

---Pulls with the user's pull.rebase/pull.ff settings; without any, merges (like VSCode).
function M.pull()
  git.run(state().root, { 'config', '--get-regexp', '^pull\\.(rebase|ff)$' }, function(_, out)
    remote('pull', vim.trim(out) == '' and { 'pull', '--no-rebase' } or { 'pull' })
  end)
end

---Pushes; a branch without an upstream is published to a remote (asked for when there are several).
function M.push()
  if state().status.upstream then
    return remote('push', { 'push' })
  end
  git.run(state().root, { 'remote' }, function(_, out)
    local remotes = vim.split(vim.trim(out), '\n', { trimempty = true })
    local function publish(name)
      if name then
        remote('push', { 'push', '--set-upstream', name, 'HEAD' })
      end
    end
    if #remotes == 0 then
      notify('no remote configured', vim.log.levels.WARN)
    elseif #remotes == 1 then
      publish(remotes[1])
    else
      require('nice-git.ui').select(remotes, { prompt = 'Publish branch to' }, publish)
    end
  end)
end

---Finishes the merge/rebase/cherry-pick/revert in progress. A merge is concluded by committing,
---so the commit box message (if any) is used.
function M.continue()
  local op = state().status.operation
  if op == 'merge' then
    require('nice-git.commit').commit()
  elseif op then
    M.run({ op, '--continue' })
  end
end

function M.abort()
  local op = state().status.operation
  if op and vim.fn.confirm('Abort the ' .. op .. '?', '&Abort\n&Cancel', 2) == 1 then
    M.run({ op, '--abort' })
  end
end

function M.skip()
  local op = state().status.operation
  if op then
    M.run({ op, '--skip' })
  end
end

---Stashes all changes, untracked files included, under an optional message.
function M.stash()
  require('nice-git.ui').input({ prompt = 'Stash message (optional): ' }, function(msg)
    if msg == nil then
      return
    end
    local args = { 'stash', 'push', '--include-untracked' }
    if vim.trim(msg) ~= '' then
      vim.list_extend(args, { '--message', vim.trim(msg) })
    end
    M.run(args)
  end)
end

function M.stash_apply(stash)
  M.run({ 'stash', 'apply', stash.ref })
end

function M.stash_pop(stash)
  M.run({ 'stash', 'pop', stash.ref })
end

function M.stash_drop(stash)
  if vim.fn.confirm('Drop ' .. stash.ref .. ' (' .. stash.message .. ')?', '&Drop\n&Cancel', 2) == 1 then
    M.run({ 'stash', 'drop', stash.ref })
  end
end

---Shows a stash's patch with Apply / Pop / Drop buttons.
function M.show_stash(stash)
  local args = { 'stash', 'show', '--patch', '--include-untracked', stash.ref }
  git.run(state().root, args, function(ok, out, err)
    if not ok then
      return notify(vim.trim(err), vim.log.levels.ERROR)
    end
    require('nice-git.diff').show_page(stash.ref, vim.split(out, '\n', { plain = true }), 'diff', stash.ref .. '  ' .. stash.message, {
      { '↓ Apply', function() M.stash_apply(stash) end },
      { '⇣ Pop', function() M.stash_pop(stash) end },
      { '✕ Drop', function() M.stash_drop(stash) end },
    })
  end)
end

---Creates a worktree for a new or existing branch next to the repository.
function M.add_worktree()
  local root = state().root
  require('nice-git.ui').input({ prompt = 'Branch for the new worktree: ' }, function(branch)
    branch = branch and vim.trim(branch)
    if not branch or branch == '' then
      return
    end
    local default = vim.fs.dirname(root) .. '/' .. vim.fs.basename(root) .. '-' .. branch:gsub('/', '-')
    require('nice-git.ui').input({ prompt = 'Worktree path: ', default = default, completion = 'dir' }, function(path)
      if not path or vim.trim(path) == '' then
        return
      end
      path = vim.fn.fnamemodify(vim.trim(path), ':p'):gsub('/$', '')
      git.run(root, { 'rev-parse', '--verify', '-q', 'refs/heads/' .. branch }, function(exists)
        M.run(exists and { 'worktree', 'add', path, branch } or { 'worktree', 'add', '-b', branch, path })
      end)
    end)
  end)
end

function M.remove_worktree(wt)
  if vim.fn.confirm('Remove worktree ' .. wt.path .. '?', '&Remove\n&Cancel', 2) == 1 then
    M.run({ 'worktree', 'remove', wt.path })
  end
end

function M.update_submodule(sm)
  M.run({ 'submodule', 'update', '--init', '--recursive', '--', sm.path })
end

local NEW = { label = '+ Create new branch…' }

---Picks a local or remote branch to switch to, or creates a new one.
function M.switch_branch()
  local fmt = '--format=%(refname:short)%00%(refname:rstrip=-2)'
  local args = { 'for-each-ref', fmt, '--sort=-committerdate', 'refs/heads', 'refs/remotes' }
  git.run(state().root, args, function(ok, out, err)
    if not ok then
      return notify(vim.trim(err), vim.log.levels.ERROR)
    end
    local current = state().status.branch
    local locals, items = {}, { NEW }
    local remotes = {}
    for _, line in ipairs(vim.split(out, '\n', { trimempty = true })) do
      local name, kind = unpack(vim.split(line, '\0', { plain = true }))
      if kind == 'refs/heads' then
        locals[name] = true
        if name ~= current then
          table.insert(items, { label = name, name = name })
        end
      elseif not name:match('/HEAD$') and name:find('/') then
        table.insert(remotes, name)
      end
    end
    for _, name in ipairs(remotes) do
      -- Remote branches that already have a local counterpart are reached through it.
      if not locals[name:gsub('^[^/]+/', '')] then
        table.insert(items, { label = name .. '  (remote)', remote = name })
      end
    end
    require('nice-git.ui').select(items, {
      prompt = 'Switch branch (on ' .. (current or '?') .. ')',
      format_item = function(item)
        return item.label
      end,
    }, function(item)
      if not item then
        return
      elseif item == NEW then
        require('nice-git.ui').input({ prompt = 'New branch name: ' }, function(name)
          if name and vim.trim(name) ~= '' then
            M.run({ 'switch', '-c', vim.trim(name) })
          end
        end)
      elseif item.remote then
        M.run({ 'switch', '--track', item.remote })
      else
        M.run({ 'switch', item.name })
      end
    end)
  end)
end

return M
