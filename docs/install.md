# Install

## Requirements

- Neovim 0.13+
- git 2.32+
- A [Nerd Font](https://www.nerdfonts.com) (v3+) in your terminal, for the icons and rounded buttons
- `termguicolors` on (the default in most terminals), so colors can be derived from your colorscheme
- `mouse=a` (the Neovim default) for mouse support
- Optional: [mini.icons](https://github.com/echasnovski/mini.icons) or
  [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) for colored file icons
- Optional: the [GitHub CLI](https://cli.github.com) (`gh`, logged in with `gh auth login`) for pull requests

## vim.pack (built in)

```lua
vim.pack.add({ 'https://github.com/mkrbz/nice-git.nvim' })
```

This follows the default branch. To pin a branch, tag or commit, use the table form:

```lua
vim.pack.add({ { src = 'https://github.com/mkrbz/nice-git.nvim', version = 'main' } })
```

- Update: `:packupdate nice-git.nvim`, review the changes, then `:write` to apply them.
- Remove: `:packdel nice-git.nvim`.

No lazy-loading setup is needed: at startup the plugin only defines the `:NiceGit` command.
If you call `require('nice-git').setup()`, do it after `vim.pack.add()`.

## lazy.nvim

```lua
{ 'mkrbz/nice-git.nvim', cmd = 'NiceGit', opts = {} }
```

`opts` is passed to `setup()`; see [Configuration](configuration.md).

## From a local clone

To track your own clone through vim.pack:

```lua
vim.pack.add({ { src = 'file://' .. vim.fn.expand('~/dev/nice-git.nvim'), name = 'nice-git.nvim' } })
```

vim.pack copies the repository into its own directory, so it only sees committed changes, and only
after `:packupdate`. To run uncommitted edits, see [Development](development.md).

## Private forks

A private fork needs your own access: use an SSH URL (`git@github.com:<owner>/nice-git.nvim`) with a key
that has access, or an HTTPS URL with a git credential helper for github.com (for example after
`gh auth setup-git`). Check access with `git ls-remote <url>`.
