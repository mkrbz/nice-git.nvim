-- Pull requests through the GitHub CLI (`gh`), which handles authentication itself.
local M = {}

-- { root, loading, list, error }; loaded on demand because it goes over the network.
M.prs = {}

local function root()
  return require('nice-git').state.root
end

function M.available()
  return vim.fn.executable('gh') == 1
end

---Runs gh in the repo; never prompts (there is no terminal).
local function gh(args, cb)
  local cmd = vim.list_extend({ 'gh' }, args)
  vim.system(cmd, { cwd = root(), text = true, env = { GH_PROMPT_DISABLED = '1', NO_COLOR = '1' } }, function(res)
    vim.schedule(function()
      cb(res.code == 0, res.stdout or '', vim.trim(res.stderr or ''))
    end)
  end)
end

local function render()
  require('nice-git.sidebar').render()
end

function M.load()
  M.prs = { root = root(), loading = true }
  render()
  local fields = 'number,title,author,headRefName,isDraft,url'
  gh({ 'pr', 'list', '--limit', '50', '--json', fields }, function(ok, out, err)
    local okjson, list = pcall(vim.json.decode, out)
    if ok and okjson then
      M.prs = { root = M.prs.root, list = list }
    else
      M.prs = { root = M.prs.root, error = err ~= '' and err or 'gh pr list failed' }
    end
    render()
  end)
end

---Loads the list the first time it's needed for the active repo.
function M.ensure_loaded()
  if M.prs.root ~= root() then
    M.load()
  end
end

local function after(label)
  return function(ok, out, err)
    if ok then
      require('nice-git.ui').notify(label .. ' done')
    else
      require('nice-git.ui').notify(label .. ' failed: ' .. (err ~= '' and err or out), vim.log.levels.ERROR)
    end
    vim.cmd.checktime()
    require('nice-git').refresh()
  end
end

function M.checkout(pr)
  gh({ 'pr', 'checkout', tostring(pr.number) }, after('checkout #' .. pr.number))
end

function M.browse(pr)
  gh({ 'pr', 'view', tostring(pr.number), '--web' }, function(ok, _, err)
    if not ok then
      require('nice-git.ui').notify(err, vim.log.levels.ERROR)
    end
  end)
end

function M.show_diff(pr)
  gh({ 'pr', 'diff', tostring(pr.number) }, function(ok, out, err)
    if not ok then
      return require('nice-git.ui').notify(err, vim.log.levels.ERROR)
    end
    require('nice-git.diff').show_page('pr:' .. pr.number, vim.split(out, '\n', { plain = true }), 'diff', '#' .. pr.number .. ' ' .. pr.title, {
      { '⎇ Checkout', function()
        M.checkout(pr)
      end },
      { '↗ Open in browser', function()
        M.browse(pr)
      end },
    })
  end)
end

---Opens GitHub's "new pull request" page for the current branch (it must be pushed first).
function M.create()
  gh({ 'pr', 'create', '--web' }, function(ok, out, err)
    if not ok then
      require('nice-git.ui').notify((err ~= '' and err or out), vim.log.levels.ERROR)
    end
  end)
end

function M.menu(pr)
  local choices = {
    { 'Show diff', M.show_diff },
    { 'Check out', M.checkout },
    { 'Open in browser', M.browse },
  }
  require('nice-git.ui').select(choices, {
    prompt = '#' .. pr.number .. ' ' .. pr.title,
    format_item = function(c)
      return c[1]
    end,
  }, function(choice)
    if choice then
      choice[2](pr)
    end
  end)
end

return M
