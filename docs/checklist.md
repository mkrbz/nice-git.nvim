# Manual check: nice-git.nvim v1

Each item was tested headlessly with simulated input. These checks cover what that can't:
the look in your terminal and font, a real mouse, and your own config and plugins.

Setup: load your local clone (see [development.md](development.md)), open a throwaway repo, and run `:NiceGit`.
Tick each box when it behaves as described. Anything that looks off is worth a note.

## Look
- [ ] Icons render as icons everywhere (panel, toolbar, menus, toasts). A wrong or missing glyph means a codepoint to fix in `lua/nice-git/theme.lua`
- [ ] Buttons look like rounded pills (the half-circle caps line up with the colored part)
- [ ] The panel has its own slightly different background; section titles are full-width bands with a count badge
- [ ] No `~` lines, no visible cursor in the panel, no stray statusline text between the header and the list
- [ ] Colors fit your colorscheme; switching colorscheme or `background` (light/dark) updates them
- [ ] Panel width (40) is comfortable; resizing it by dragging its border keeps the Commit button full width
- [ ] The panel opens on the right; with `setup({ position = 'left' })` it opens on the left, in the diff tab too

## Hover and mouse
- [ ] Moving the mouse over a file row highlights it and shows its open / discard / stage icons
- [ ] Resting on an icon for a moment shows a tooltip ("Stage", "Discard Changes"…)
- [ ] Leaving the panel hides the icons; after closing the panel, `:set mousemoveevent?` is back to what you had
- [ ] Single clicks work even when another window had focus; fast repeated clicks (stage several files) each register
- [ ] Clicking Stage and then quickly clicking Commit doesn't leave you in Visual mode
- [ ] Dragging a file from Changes to Staged (and back) works; the target section highlights while dragging
- [ ] Right-click a file: menu opens at the pointer; pressing `m` instead opens it at the row

## Panel and commit
- [ ] Typing a message in the bordered box and clicking **Commit** commits; the box clears and shrinks back
- [ ] A long message makes the box grow (up to 5 lines) and the button moves down with it
- [ ] `<C-CR>` commits from insert mode (if your terminal sends it; `<C-s>` otherwise)
- [ ] Commit `▾` menu: Commit (Amend), Commit All, Edit Last Commit Message, Stash All Changes each work
- [ ] With nothing staged, Commit offers to stage all tracked changes
- [ ] Discard on a tracked file asks, then restores it; on an untracked file it asks, then deletes it
- [ ] Saving a file in another window, or running `git add` in a shell, updates the panel within a moment

## Workspace toggle
- [ ] With the panel, a diff and the history open, `:NiceGit toggle` closes all of them and leaves you in your editor tab
- [ ] `:NiceGit toggle` again brings back the panel, the history tab and the diff (same file, mode and cursor), focused where you were
- [ ] "Hide nice-git" in the panel's `⋯` menu does the same; with nothing hidden, the toggle opens the panel

## Toasts
- [ ] Commit / push / errors show a small message bottom right that disappears by itself
- [ ] Clicking a toast dismisses it; errors stay a bit longer

## Diff view
- [ ] Clicking a file opens a tab with the whole file side by side, cursor on the first change
- [ ] Removed lines leave a hatched gap on the other side; colored bars in the sign column mark changes
- [ ] Scrolling either pane with the mouse wheel keeps both panes aligned, also while the panel has focus
- [ ] You can edit the right side and the diff (and the "n changes" count) updates as you type
- [ ] **Split | Inline** switch: inline shows removed lines in red with syntax colors, changed words stronger
- [ ] Toolbar buttons stay visible in a narrow window (the file label shortens first)
- [ ] `]c` / `[c` and the arrow icons jump between changes in both modes
- [ ] **Stage** stages only the change under the cursor (check with `git diff --cached`); **Discard** reverts and saves it
- [ ] Opening a file from Staged shows HEAD ↔ Index with **Unstage**
- [ ] Closing the diff tab leaves no leftover keymaps/highlights in the file

## Sync and branches
- [ ] Fetch, pull and push icons work against your real remote (SSH key / credential helper)
- [ ] While one runs, the branch row shows a spinner; ahead/behind counts update after
- [ ] Pushing a new branch publishes it with an upstream
- [ ] Clicking the branch name lists branches; switching, creating, and checking out a remote-only branch work
- [ ] A failing remote op (e.g. no network) shows git's error in a toast instead of hanging

## Merge conflicts
- [ ] During a merge the header shows MERGE with Continue / Abort pills
- [ ] A conflicted file (`!`) opens with highlighted regions and **Accept Current / Accept Incoming / Accept Both** pills on the first marker line, "Incoming Change" on the last
- [ ] The pills work with a mouse, also with line numbers enabled; `co` / `ct` / `cb` / `c0` work from the keyboard
- [ ] **Mark Resolved** saves and stages the file; **Continue** finishes the merge
- [ ] Rebase with a conflict shows REBASE with Continue / Skip / Abort

## Stash
- [ ] Stash All Changes (Commit `▾` or title bar menu) asks for an optional message and stashes everything, untracked included
- [ ] STASHES section appears; clicking a stash shows its patch with Apply / Pop / Drop buttons
- [ ] Row icons apply and drop (drop asks first)

## History
- [ ] The history icon, `l`, or `:NiceGit log` opens the graph in its own tab
- [ ] Each line of history has its own color; merges and branch-offs join with rounded corners; HEAD, branches, tags and remotes are labels
- [ ] Rows highlight under the mouse; clicking a commit lists its files; clicking a file opens that commit's diff
- [ ] Right-click a commit opens the menu (Show commit, Copy hash, Interactive rebase)
- [ ] **All branches** toggle and **Load more** at the bottom work
- [ ] Committing while the log is visible adds the new commit to it

## Blame
- [ ] `:NiceGit blame_line` shows "author, time ago · summary" at the end of the cursor line and follows the cursor
- [ ] Unsaved new lines show "Uncommitted changes"
- [ ] `:NiceGit blame` opens a side panel in columns (hash, author, age; last week's changes stand out) that scrolls with the file
- [ ] Clicking a blame line shows that commit; toggling again closes the panel cleanly

## Interactive rebase
- [ ] Log → right-click → **Interactive rebase from here…** opens a centered rounded window
- [ ] **Dragging rows with a real mouse reorders them.** This is the one mouse path the tests couldn't drive, because headless Neovim doesn't route the mouse to floating windows
- [ ] Clicking an action pill cycles it; reword asks for the new message
- [ ] **Start Rebase** runs it; the result in the log matches the plan (reorder, drop, squash, reword)

## Worktrees and submodules
- [ ] WORKTREES (collapsed by default) lists worktrees; its `+` creates one for a new or existing branch
- [ ] Clicking a worktree switches the panel to it (tab-local `:tcd`); the trash icon removes one
- [ ] In a repo with submodules: SUBMODULES lists them, the refresh icon updates one, clicking enters one, "Parent repository" in the header returns

## Pull requests
- [ ] With `gh` logged in, expanding PULL REQUESTS lists open PRs (nothing loads until you expand)
- [ ] Clicking a PR offers Show diff / Check out / Open in browser, and each works
- [ ] The external-link icon opens the PR in the browser; the section's create icon opens the new-PR page for the pushed branch
- [ ] Logged out or not a GitHub repo: a readable error appears in the section

## Compatibility
- [ ] Works with your usual config and plugins loaded (no keymap clashes you care about, e.g. `<leader>hs`/`<leader>hr`, `co`/`ct`/`cb` in conflict files)
- [ ] With `setup({ native_ui = true })`, menus and prompts use your `vim.ui` provider and messages use `vim.notify`
- [ ] Startup cost: nothing loads until `:NiceGit` is used
