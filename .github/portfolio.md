## Why

Neovim has excellent Git plugins, but they are built for the keyboard and look like text. I wanted the
experience of VSCode's Source Control view inside Neovim: a panel you can click, diffs you can edit,
buttons where you expect them, and every action still reachable from the keyboard.

## How it works

**Async Git, no dependencies.** Every Git command runs through `vim.system` with a callback, so the editor
never waits. Status comes from `git status --porcelain=v2`, and file watchers on the repository plus a short
debounce keep the panel current while you edit, without polling.

**An interface made of text cells.** A terminal has no pixels, so the look comes from what cells can do:
colored surfaces derived from the active colorscheme, Nerd Font icons and half-circle caps that turn text
into rounded buttons, right-aligned virtual text for row actions, and floating windows for menus,
tooltips and notifications. Hover works by tracking mouse movement while the panel is visible.

**Diffs you can edit.** Side-by-side mode builds on Neovim's own diff mode. Inline mode keeps a single
editable buffer and draws removed lines as virtual lines, with syntax colors from a Treesitter parse of
the old version and word-level highlights from a token diff. Staging a single change writes a new blob
straight into the index.

**A graph and a rebase without an editor.** The commit graph is laid out from commit parents, one lane per
line of history. The rebase planner hands its plan to Git through `GIT_SEQUENCE_EDITOR`, and rewords
become amend steps, so no editor ever opens.

## Testing

The interface is tested end to end in headless Neovim. Scenarios create real repositories, then drive the
plugin with real mouse events: clicks, drags, double clicks and wheel scrolls. That surfaced problems a
unit test would miss, such as quick clicks falling into Visual mode and a Neovim bug where scrolling an
unfocused pane breaks `scrollbind`.

The screenshots come from a small client that attaches to Neovim as a UI over its msgpack-RPC protocol,
records exactly what Neovim draws, and renders it with the same Nerd Font.
