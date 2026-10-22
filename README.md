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

The repo is private, so whatever installs it needs your own access to it.
Replace `<you>` with the GitHub account or org that owns the repo.

### vim.pack (built-in)

**From GitHub**, in `init.lua`:

```lua
vim.pack.add({ 'git@github.com:<you>/nice-git.nvim' })
```

SSH needs a key with access to the repo. To use HTTPS instead
(`'https://github.com/<you>/nice-git.nvim'`), git needs a credential helper for github.com,
for example after running `gh auth setup-git`. Check access first with
`git ls-remote git@github.com:<you>/nice-git.nvim`.

**From a local clone:**

```lua
vim.pack.add({ { src = 'file://' .. vim.fn.expand('~/dev/nice-git.nvim'), name = 'nice-git.nvim' } })
```

vim.pack clones the repo into its own directory, so it only sees **committed** changes,
and only after `:packupdate`. To try uncommitted edits while working on the plugin,
skip vim.pack and put the working copy on the runtimepath instead:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand('~/dev/nice-git.nvim'))
```

Both GitHub and local installs follow the default branch, since there are no release tags yet.
Pin a branch or commit with `version = '<branch or hash>'` in the spec.

To update, run `:packupdate nice-git.nvim`, review the changes, then `:write` to apply them.
To remove, run `:packdel nice-git.nvim`.
No lazy-loading setup is needed: at startup the plugin only defines the `:NiceGit` command.

### lazy.nvim

```lua
{ url = 'git@github.com:<you>/nice-git.nvim.git', name = 'nice-git.nvim', cmd = 'NiceGit', opts = {} }
-- or a local clone (uses the working copy, uncommitted edits included)
{ dir = '~/dev/nice-git.nvim', name = 'nice-git.nvim', cmd = 'NiceGit', opts = {} }
```

### Configuration

`setup()` is optional. With vim.pack, call it after `vim.pack.add()`:

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
