# Manual check: nice-git.nvim v1

Each item was tested headlessly with simulated input. These checks cover what that can't:
the look, a real terminal's mouse, and your own config and plugins.

Setup: install from your local clone (see README), open a throwaway repo, and run `:NiceGit`.
Tick each box when it behaves as described. Anything that looks off is worth a note.

## Look and feel
- [ ] Panel on the left: commit box on top, file list below, "SOURCE CONTROL · <repo>" title
- [ ] Colors look right in your colorscheme (status letters, section titles, buttons)
- [ ] File icons appear if you use nvim-web-devicons/mini.icons; otherwise a clean `•`
- [ ] Buttons at the right edge line up and don't cover long file names too badly
- [ ] Resizing the panel by dragging its border works and the buttons stay at the right edge

## Panel and staging (1)
- [ ] Single click on `+` / `−` stages / unstages, even when another window had focus
- [ ] Dragging a file from Changes to Staged (and back) works; the target section highlights while dragging
- [ ] Fast repeated clicks (stage several files quickly) each register
- [ ] `↺` on a tracked file asks, then restores it; on an untracked file it asks, then deletes it
- [ ] Editing a file in another window and saving updates the panel within a moment
- [ ] Changes made outside Neovim (e.g. `git add` in a shell) show up when you come back

## Commit box (1)
- [ ] Typing a message and clicking **Commit** commits; the box clears
- [ ] `<C-CR>` commits from insert mode (if your terminal sends it; `<C-s>` otherwise)
- [ ] **Amend** prefills the last message; committing amends instead of adding a commit
- [ ] With nothing staged, Commit offers to stage all tracked changes

## Diff view (2, 3)
- [ ] Clicking a file opens a new tab with the whole file side by side, cursor on the first change
- [ ] You can edit the right side (working file) and the diff updates as you type
- [ ] **Inline** toolbar button: one pane, removed lines red above, added lines green; editing updates live
- [ ] `]c` / `[c` and the `↑` / `↓` buttons jump between changes in both modes
- [ ] **Stage hunk** stages only the change under the cursor (check with `git diff --cached`)
- [ ] **Discard hunk** reverts just that change and saves the file
- [ ] Opening a file from Staged shows HEAD ↔ Index with **Unstage hunk**
- [ ] Closing the diff tab leaves no leftover keymaps/highlights in the file

## Sync and branches (4, 5)
- [ ] `⟳` fetch, `↓` pull, `↑` push work against your real remote (SSH key / credential helper)
- [ ] Header shows ↑/↓ counts and "push…" etc. while running
- [ ] Pushing a new branch publishes it with an upstream
- [ ] Clicking the branch name lists branches; switching, creating, and checking out a remote-only branch work
- [ ] A failing remote op (e.g. no network) shows git's error instead of hanging

## Merge conflicts (6)
- [ ] During a merge the panel shows "⚠ MERGE" with Continue / Abort
- [ ] Clicking a conflicted file (`!`) opens it with highlighted regions and **Accept Current │ Accept Incoming │ Accept Both** over each `<<<<<<<` line
- [ ] Those buttons work with a mouse, also with line numbers enabled
- [ ] `co` / `ct` / `cb` / `c0` resolve the conflict under the cursor
- [ ] **Mark resolved** saves and stages the file; **Continue** finishes the merge
- [ ] Rebase with a conflict shows "⚠ REBASE" with Continue / Skip / Abort

## Stash (7)
- [ ] **Stash** asks for an optional message and stashes everything (including untracked)
- [ ] STASHES section appears; clicking a stash shows its patch with Apply / Pop / Drop buttons
- [ ] Row buttons `↓` (apply) and `✕` (drop, asks first) work

## History (8)
- [ ] `☰` / `l` / `:NiceGit log` opens the graph in its own tab, with branch lines in color
- [ ] Clicking a commit lists its files; clicking a file opens that commit's diff
- [ ] Right-click a commit opens the menu (Show commit, Copy hash, Interactive rebase)
- [ ] **All branches** toggle and **Load more** at the bottom work
- [ ] Committing while the log is visible adds the new commit to it

## Blame (9)
- [ ] `:NiceGit blame_line` shows "author, time ago · summary" at the end of the cursor line and follows the cursor
- [ ] Unsaved new lines show "Uncommitted changes"
- [ ] `:NiceGit blame` opens a side panel that scrolls together with the file
- [ ] Clicking a blame line shows that commit; toggling again closes the panel cleanly

## Interactive rebase (10)
- [ ] Log → right-click → **Interactive rebase from here…** opens a centered float
- [ ] **Dragging rows with a real mouse reorders them.** This is the one mouse path the tests couldn't drive, because headless Neovim doesn't route mouse input to floats.
- [ ] Clicking the `[pick]` badge cycles actions; reword asks for the new message
- [ ] **Start** runs it; the result in the log matches the plan (reorder, drop, squash, reword)

## Worktrees and submodules (11)
- [ ] WORKTREES (collapsed by default) lists worktrees; `+` creates one for a new or existing branch
- [ ] Clicking a worktree switches the panel to it (tab-local `:tcd`); `✕` removes one
- [ ] In a repo with submodules: SUBMODULES lists them, `⟳` updates, clicking enters one, "↖ Parent repository" returns

## Pull requests (12)
- [ ] With `gh` logged in, expanding PULL REQUESTS lists open PRs (nothing loads until you expand)
- [ ] Clicking a PR offers Show diff / Check out / Open in browser, and each works
- [ ] `↗` opens the PR in the browser; `+` opens the create page for the pushed branch
- [ ] Logged out or not a GitHub repo: a readable error appears in the section

## Compatibility
- [ ] Works with your usual config and plugins loaded (no keymap clashes you care about, e.g. `<leader>hs`/`<leader>hr`, `co`/`ct`/`cb` in conflict files)
- [ ] Startup cost: nothing loads until `:NiceGit` is used
