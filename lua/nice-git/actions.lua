-- Repo-level commands triggered from the panel: sync with remotes and branch switching.
local git = require('nice-git.git')

local M = {}

local function state()
  return require('nice-git').state
end

local function notify(msg, level)
  vim.notify('nice-git: ' .. msg, level)
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
      vim.ui.select(remotes, { prompt = 'Publish branch to' }, publish)
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
    vim.ui.select(items, {
      prompt = 'Switch branch (on ' .. (current or '?') .. ')',
      format_item = function(item)
        return item.label
      end,
    }, function(item)
      if not item then
        return
      elseif item == NEW then
        vim.ui.input({ prompt = 'New branch name: ' }, function(name)
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
