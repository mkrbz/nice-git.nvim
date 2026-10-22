# nice-git.nvim

A VSCode-style, mouse-friendly Source Control panel for Neovim.

> Early scaffold: status panel, staging and full-file diffs only.

## Requirements

- Neovim 0.13+
- git 2.30+
- Optional: a Nerd Font plus [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
  or [mini.icons](https://github.com/echasnovski/mini.icons) for file icons

## Install

With lazy.nvim:

```lua
{ 'mkrbz/nice-git.nvim', cmd = 'NiceGit', opts = {} }
```

Or put the directory on your `runtimepath`. `setup()` is optional.

```lua
require('nice-git').setup({ width = 35, debounce = 100 })
```

## Usage

`:NiceGit` toggles the panel.

| Mouse | Key | Action |
|---|---|---|
| click file | `<CR>` | open full-file side-by-side diff |
| click section | `<CR>` | collapse / expand |
| click `+` / `−` | `-` | stage / unstage (file or whole section) |
| drag file between sections | | stage / unstage |
| | `R` | refresh |
| | `q` | close |

The panel refreshes on its own when files are saved, the index or HEAD changes, or Neovim regains focus.
