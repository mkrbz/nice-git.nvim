if vim.g.loaded_nice_git then
  return
end
vim.g.loaded_nice_git = true

vim.api.nvim_create_user_command('NiceGit', function()
  require('nice-git').toggle()
end, { desc = 'Toggle the nice-git Source Control panel' })
