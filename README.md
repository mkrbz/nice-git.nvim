# nice-git.nvim

A VSCode-style, mouse-friendly git interface for Neovim. Everything is clickable, and every click also has a key.

## Requirements

- Neovim 0.13+
- git 2.32+
- A [Nerd Font](https://www.nerdfonts.com) (v3+) in your terminal, for the icons and rounded buttons
- `termguicolors` on (the default in most terminals), so colors can be derived from your colorscheme
- Optional: [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
  or [mini.icons](https://github.com/echasnovski/mini.icons) for colored file icons
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
  width = 40,          -- panel width
  position = 'right',  -- or 'left'
  debounce = 100,      -- ms to wait after file changes before refreshing
  diff_mode = 'split', -- or 'inline'
  repaint_after_scroll = true, -- repaint once after the side-by-side panes scroll (clears stale strips some terminals leave)
  native_ui = false,   -- true: use vim.notify / vim.ui.select / vim.ui.input (e.g. with telescope or snacks)
  icons = {},          -- override any icon, e.g. { stash = '' }; see lua/nice-git/theme.lua
})
```

Colors come from your colorscheme and follow it when it changes. To restyle a part, override its
`NiceGit*` highlight group, for example `vim.api.nvim_set_hl(0, 'NiceGitPill', { fg = '#000000', bg = '#7aa2f7' })`.

While the panel is visible, `mousemoveevent` is switched on (and restored when it closes) so rows can react to hover.

## Commands

| Command | |
|---|---|
| `:NiceGit` | Toggle the Source Control panel in the current tab |
| `:NiceGit toggle` | Hide the whole workspace (panels, diff tab, history tab) and bring it back exactly as it was |
| `:NiceGit log` | Commit graph |
| `:NiceGit blame` | Toggle the blame side panel for the current file |
| `:NiceGit blame_line` | Toggle blame text on the cursor line |

To flip between your code and nice-git with one key, map the workspace toggle, for example:

```lua
vim.keymap.set('n', '<leader>g', '<cmd>NiceGit toggle<cr>', { desc = 'nice-git' })
```

Hiding closes nice-git's windows and tabs but keeps their state; showing reopens them with the same file,
diff mode and cursor, and returns you to the tab you were in.

## Panel

The header holds the commit message box, a **Commit** button (its `▾` opens Commit (Amend), Commit All,
Edit Last Commit Message and Stash All Changes), and the branch with fetch, pull and push icons. The title bar
has icons for history, refresh and a menu with more actions. Below it, changes are grouped in sections.
Hover a file (or move the cursor to it) to see its buttons; right-click it for a menu.

| Mouse | Key | Action |
|---|---|---|
| click branch name | `b` | switch, create, or track a branch |
| fetch / pull / push icons | `f` / `p` / `P` | sync with the remote |
| history icon (title bar) | `l` | commit graph |
| Commit | `c` (focus message box), then `<C-CR>` or `<C-s>` | commit |
| click file | `<CR>` | open its full-file diff (conflicted files open the conflict view) |
| open-file icon | `o` | open the file itself |
| stage / unstage icon | `-` | stage / unstage the file, or the whole section on its title |
| discard icon | `x` | discard changes (deletes untracked files) |
| drag a file between sections | | stage / unstage |
| right-click | `m` | context menu |
| click section title | `<CR>` | collapse / expand |
| Continue / Skip / Abort | | finish an in-progress merge, rebase, cherry-pick or revert |
| | `R` / `q` | refresh / close |

The panel also has sections for worktrees, submodules, pull requests and stashes. Clicking a worktree or submodule makes it the active repo for the tab.

## Diff view

The diff always shows the whole file. The toolbar's **Split | Inline** switch picks between side by side (old version on the left,
read-only) and inline (removed lines shown in red, with their syntax colors, above the lines that replaced them; changed words
are highlighted). Colored bars in the sign column mark every change. The working-tree side is your real buffer,
so you can edit it directly and the diff updates as you type.

| Toolbar | Key | |
|---|---|---|
| `↑` / `↓` icons | `[c` / `]c` | previous / next change |
| Stage / Unstage | `<leader>hs` | stage or unstage the change under the cursor |
| Discard | `<leader>hr` | revert the change under the cursor |

**Conflicts:** click **Accept Current / Accept Incoming / Accept Both** on the conflict's first line, or press `co` / `ct` / `cb` / `c0`
(the last one keeps neither side). Then click **Mark Resolved**.

## History

The graph draws each line of history in its own color, with branches, tags and remotes as labels. Click a commit to expand
its files, and click a file to diff it. Right-click (or `m`) opens a menu with Show commit, Copy hash and
**Interactive rebase from here…**. In the rebase planner, drag rows to reorder them, click an action (or press
`p`/`r`/`e`/`s`/`f`/`d`) to change it, then click **Start Rebase**.

## Development

Work on the plugin from the local clone, not from an installed copy.

**Load the working copy.** In `init.lua`, put the clone on the runtimepath and remove any `vim.pack.add`
(or lazy.nvim) entry for nice-git, so only one copy exists:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand('~/dev/nice-git.nvim'))
```

Uncommitted edits are picked up as soon as Neovim restarts; there is nothing to install or update.
If an old `vim.pack` copy is still on disk, remove it with `:packdel nice-git.nvim`.

**See a change.** Save your edit, then run `:restart` (Neovim reopens with the same session), and `:NiceGit`.
Restarting is the reliable way: the plugin keeps buffers, autocommands and timers that a plain
`:lua package.loaded[...] = nil` reload would leave behind.

**Rule out your config.** To check whether something comes from the plugin or from your setup,
start a clean Neovim inside any git repo:

```sh
nvim --clean --cmd 'set rtp^=~/dev/nice-git.nvim' -c 'set termguicolors' -c NiceGit
```

**Smoke check** (headless, prints the parsed status):

```sh
nvim --headless --clean --cmd 'set rtp^=~/dev/nice-git.nvim' -c NiceGit \
  -c "lua vim.wait(3000, function() return require('nice-git').state.status end); print(vim.inspect(require('nice-git').state.status))" \
  -c 'qa!'
```

**Back to a normal install.** When you stop working on it, swap the runtimepath line for the
`vim.pack.add` entry from [Install](#install-private-repository); it then follows committed changes
through `:packupdate`.

## Notes

- Nothing is stored on disk. Credentials always come from your git credential helper, SSH agent, or `gh`.
- Pull without `pull.rebase`/`pull.ff` configured merges, like VSCode does.
