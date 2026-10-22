# nice-git.nvim

A VSCode-style, mouse-friendly git interface for Neovim. Everything is clickable, and every click also has a key.

## Requirements

- Neovim 0.13+
- git 2.32+
- Optional: a Nerd Font plus [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
  or [mini.icons](https://github.com/echasnovski/mini.icons) for file icons
- Optional: [GitHub CLI](https://cli.github.com) (`gh`, logged in with `gh auth login`) for pull requests
- `set mouse=a` (the Neovim default) for mouse support

## Install (private repository)

The repo is private, so your plugin manager has to reach it with your own credentials.
Replace `<you>` with the GitHub account or org that owns the repo.

**From a local clone** (simplest; no network auth involved):

```lua
-- lazy.nvim
{ dir = '~/dev/nice-git.nvim', name = 'nice-git.nvim', cmd = 'NiceGit', opts = {} }

-- or without a plugin manager
vim.opt.runtimepath:prepend(vim.fn.expand('~/dev/nice-git.nvim'))
```

**From GitHub over SSH** (needs an SSH key that has access to the repo):

```lua
-- lazy.nvim
{ url = 'git@github.com:<you>/nice-git.nvim.git', name = 'nice-git.nvim', cmd = 'NiceGit', opts = {} }

-- built-in vim.pack
vim.pack.add({ { src = 'git@github.com:<you>/nice-git.nvim' } })
```

HTTPS URLs also work if git has a credential helper for github.com (for example after `gh auth setup-git`).
Check access first with `git ls-remote git@github.com:<you>/nice-git.nvim.git`.

`setup()` is optional:

```lua
require('nice-git').setup({
  width = 35,          -- panel width
  debounce = 100,      -- ms to wait after file changes before refreshing
  diff_mode = 'split', -- or 'inline'
})
```

## Commands

| Command | |
|---|---|
| `:NiceGit` | Toggle the Source Control panel |
| `:NiceGit log` | Commit graph |
| `:NiceGit blame` | Toggle the blame side panel for the current file |
| `:NiceGit blame_line` | Toggle blame text on the cursor line |

## Panel

The commit message box is at the top, with the file list below it.

| Mouse | Key | Action |
|---|---|---|
| click branch name | `b` | switch, create, or track a branch |
| `☰` / `⟳` / `↓` / `↑` | `l` / `f` / `p` / `P` | history / fetch / pull / push |
| Commit / Amend / Stash | `c` (focus message box) | commit, toggle amend, stash all |
| | `<C-CR>` or `<C-s>` in message box | commit |
| click file | `<CR>` | open full-file diff (conflicted files open the conflict view) |
| click section title | `<CR>` | collapse / expand |
| `+` / `−` | `-` | stage / unstage file or whole section |
| `↺` | `x` | discard changes (deletes untracked files) |
| drag file between sections | | stage / unstage |
| Continue / Skip / Abort | | finish an in-progress merge, rebase, cherry-pick or revert |
| | `R` / `q` | refresh / close |

The panel also has sections for worktrees, submodules, pull requests and stashes. Clicking a worktree or submodule makes it the active repo for the tab.

## Diff view

The diff always shows the whole file. The toolbar switches between **side by side** (old version on the left, read-only)
and **inline** (removed lines appear in red above the line that replaced them). The working-tree side is your real buffer,
so you can edit it directly and the diff updates as you type.

| Toolbar | Key | |
|---|---|---|
| `↑` / `↓` | `[c` / `]c` | previous / next change |
| Stage hunk / Unstage hunk | `<leader>hs` | stage or unstage the change under the cursor |
| Discard hunk | `<leader>hr` | revert the change under the cursor |

**Conflicts:** click **Accept Current / Incoming / Both** on the `<<<<<<<` line, or press `co` / `ct` / `cb` / `c0`
(the last one keeps neither side). Then click **Mark resolved**.

## History

Click a commit to expand its files, and click a file to diff it. Right-click (or `m`) opens a menu with Show commit,
Copy hash and **Interactive rebase from here…**. In the rebase planner, drag rows to reorder them, click the action badge
(or press `p`/`r`/`e`/`s`/`f`/`d`) to change it, then click **Start**.

## Notes

- Nothing is stored on disk. Credentials always come from your git credential helper, SSH agent, or `gh`.
- Pull without `pull.rebase`/`pull.ff` configured merges, like VSCode does.
