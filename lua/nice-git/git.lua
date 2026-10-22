-- Async git plumbing. Every call goes through vim.system and reports back on the main loop.
local M = {}

---@param root string
---@param args string[]
---@param cb fun(ok: boolean, stdout: string, stderr: string)
---@param opts? { stdin?: string, env?: table<string, string> }
function M.run(root, args, cb, opts)
  opts = opts or {}
  -- --no-optional-locks keeps `git status` from rewriting the index, which would retrigger our watcher.
  local cmd = vim.list_extend({ 'git', '-C', root, '--no-optional-locks' }, args)
  -- Never wait on a terminal prompt or an editor: there is no terminal, credentials come from
  -- helpers/agents, and messages are passed explicitly (merges keep git's default message).
  local env = vim.tbl_extend('force', { GIT_TERMINAL_PROMPT = '0', GIT_EDITOR = 'true' }, opts.env or {})
  vim.system(cmd, { text = true, stdin = opts.stdin, env = env }, function(res)
    vim.schedule(function()
      cb(res.code == 0, res.stdout or '', res.stderr or '')
    end)
  end)
end

---@param dir string
---@param cb fun(root?: string, gitdir?: string, err?: string)
function M.resolve(dir, cb)
  M.run(dir, { 'rev-parse', '--show-toplevel', '--absolute-git-dir' }, function(ok, out, err)
    if not ok then
      return cb(nil, nil, vim.trim(err))
    end
    local lines = vim.split(vim.trim(out), '\n', { plain = true })
    cb(lines[1], lines[2])
  end)
end

-- Number of space-separated fields between XY and the path for each porcelain v2 entry kind.
local FIELDS = { ['1'] = 6, ['2'] = 7, u = 8 }

---@param root string
---@param cb fun(status?: table, err?: string)
function M.status(root, cb)
  local args = { 'status', '--porcelain=v2', '--branch', '-z', '--untracked-files=all' }
  M.run(root, args, function(ok, out, err)
    if not ok then
      return cb(nil, vim.trim(err))
    end
    local s = { has_head = true, staged = {}, changes = {}, untracked = {} }
    local items = vim.split(out, '\0', { plain = true })
    local i = 1
    while i <= #items do
      local line = items[i]
      local kind = line:sub(1, 1)
      if kind == '#' then
        local key, val = line:match('^# (%S+) (.*)$')
        if key == 'branch.head' then
          s.branch = val
        elseif key == 'branch.oid' then
          s.has_head = val ~= '(initial)'
        elseif key == 'branch.upstream' then
          s.upstream = val
        elseif key == 'branch.ab' then
          local a, b = val:match('^%+(%d+) %-(%d+)$')
          s.ahead, s.behind = tonumber(a), tonumber(b)
        end
      elseif FIELDS[kind] then
        local x, y = line:sub(3, 3), line:sub(4, 4)
        local path = line:match('^' .. kind .. ' .. ' .. ('%S+ '):rep(FIELDS[kind]) .. '(.*)$')
        local orig
        if kind == '2' then
          i = i + 1
          orig = items[i]
        end
        if kind == 'u' then
          table.insert(s.changes, { path = path, status = 'U' })
        else
          if x ~= '.' then
            table.insert(s.staged, { path = path, orig = orig, status = x })
          end
          if y ~= '.' then
            table.insert(s.changes, { path = path, status = y })
          end
        end
      elseif kind == '?' then
        table.insert(s.untracked, { path = line:sub(3), status = '?' })
      end
      i = i + 1
    end
    cb(s)
  end)
end

local function paths(entries)
  local list = {}
  for _, e in ipairs(entries) do
    table.insert(list, e.path)
    if e.orig then
      table.insert(list, e.orig)
    end
  end
  return list
end

function M.stage(root, entries, cb)
  M.run(root, vim.list_extend({ 'add', '-A', '--' }, paths(entries)), cb)
end

function M.unstage(root, entries, has_head, cb)
  local args = has_head and { 'restore', '--staged', '--' } or { 'rm', '-r', '-q', '--cached', '--' }
  M.run(root, vim.list_extend(args, paths(entries)), cb)
end

---Restores tracked files to their index version.
function M.discard(root, entries, cb)
  M.run(root, vim.list_extend({ 'restore', '--' }, paths(entries)), cb)
end

---Replaces the index version of `path` with `lines` (used for hunk staging).
function M.write_index(root, path, lines, cb)
  M.run(root, { 'ls-files', '-s', '--', path }, function(_, out)
    local mode = out:match('^(%d+)') or (vim.fn.executable(root .. '/' .. path) == 1 and '100755' or '100644')
    M.run(root, { 'hash-object', '-w', '--stdin', '--path=' .. path }, function(ok, sha, err)
      if not ok then
        return cb(false, '', err)
      end
      M.run(root, { 'update-index', '--add', '--cacheinfo', mode .. ',' .. vim.trim(sha) .. ',' .. path }, cb)
    end, { stdin = #lines == 0 and '' or table.concat(lines, '\n') .. '\n' })
  end)
end

---Contents of `rev:path` (e.g. "HEAD:a.lua", ":a.lua" for the index); empty when it doesn't exist.
---@param cb fun(lines: string[])
function M.show(root, spec, cb)
  M.run(root, { 'show', spec }, function(ok, out)
    local lines = ok and vim.split(out, '\n', { plain = true }) or {}
    if lines[#lines] == '' then
      table.remove(lines)
    end
    cb(lines)
  end)
end

return M
