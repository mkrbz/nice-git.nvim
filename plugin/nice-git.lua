if vim.g.loaded_nice_git then
  return
end
vim.g.loaded_nice_git = true

local commands = {
  log = function()
    require('nice-git.log').open()
  end,
  blame = function()
    require('nice-git.blame').toggle_panel()
  end,
  blame_line = function()
    require('nice-git.blame').toggle_line()
  end,
}

vim.api.nvim_create_user_command('NiceGit', function(opts)
  local cmd = commands[opts.fargs[1]]
  if cmd then
    cmd()
  elseif opts.fargs[1] then
    vim.notify('nice-git: unknown subcommand ' .. opts.fargs[1], vim.log.levels.ERROR)
  else
    require('nice-git').toggle()
  end
end, {
  nargs = '?',
  desc = 'Toggle the nice-git Source Control panel, or run a subcommand',
  complete = function()
    return vim.tbl_keys(commands)
  end,
})
