# Development

Work on the plugin from a local clone, not from an installed copy.

## Load the working copy

In `init.lua`, put the clone on the runtimepath and remove any `vim.pack.add` (or lazy.nvim) entry for
nice-git, so only one copy exists:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand('~/dev/nice-git.nvim'))
```

Uncommitted edits are picked up as soon as Neovim restarts; there is nothing to install or update.
If an old vim.pack copy is still on disk, remove it with `:packdel nice-git.nvim`.

## See a change

Save your edit, run `:restart` (Neovim reopens with the same session), then `:NiceGit`. Restarting is
the reliable way: the plugin keeps buffers, autocommands and timers that a plain
`:lua package.loaded[...] = nil` reload would leave behind.

## Rule out your config

To check whether something comes from the plugin or from your setup, start a clean Neovim inside any
git repository:

```sh
nvim --clean --cmd 'set rtp^=~/dev/nice-git.nvim' -c 'set termguicolors' -c NiceGit
```

## Smoke check

Headless; prints the parsed status:

```sh
nvim --headless --clean --cmd 'set rtp^=~/dev/nice-git.nvim' -c NiceGit \
  -c "lua vim.wait(3000, function() return require('nice-git').state.status end); print(vim.inspect(require('nice-git').state.status))" \
  -c 'qa!'
```

## Manual checks

[checklist.md](checklist.md) lists what to try by hand: the look in your terminal and font, a real
mouse, and your own config.

## Back to a normal install

When you stop working on it, swap the runtimepath line for the `vim.pack.add` entry from
[Install](install.md); it then follows committed changes through `:packupdate`.
