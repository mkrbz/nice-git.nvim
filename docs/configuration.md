# Configuration

`setup()` is optional. These are the defaults:

```lua
require('nice-git').setup({
  width = 40,                  -- panel width
  position = 'right',          -- or 'left'
  debounce = 100,              -- ms to wait after file changes before refreshing
  diff_mode = 'split',         -- or 'inline'
  repaint_after_scroll = true, -- repaint once after side-by-side panes scroll (clears stale strips some terminals leave)
  native_ui = false,           -- true: use vim.notify / vim.ui.select / vim.ui.input instead of nice-git's floats
  icons = {},                  -- override any icon, e.g. { stash = '' }
})
```

## Colors

Colors are derived from your colorscheme (its normal, diff and accent colors) and follow it when it, or
`background`, changes. To restyle a part, override its `NiceGit*` highlight group after your colorscheme
loads, for example:

```lua
vim.api.nvim_set_hl(0, 'NiceGitPill', { fg = '#1f1f28', bg = '#7e9cd8', bold = true })
```

Without `termguicolors`, the groups fall back to links to standard groups.

## Icons

Icons are [codicons](https://microsoft.github.io/vscode-codicons/) from your Nerd Font. The full list of
names is at the top of `lua/nice-git/theme.lua`; override any of them with `icons`. File icons come from
mini.icons or nvim-web-devicons when either is installed.

## Pickers and messages

With `native_ui = true`, menus and prompts go through `vim.ui.select` / `vim.ui.input` (so a picker like
telescope or snacks can handle them), and messages through `vim.notify`.
