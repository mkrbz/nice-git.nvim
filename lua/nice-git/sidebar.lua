-- Source Control panel: a full-height column (right by default) of two stacked windows. The header
-- (title bar, commit box, Commit button, branch/sync row) has a fixed size; the list below scrolls.
local api = vim.api
local git = require('nice-git.git')
local theme = require('nice-git.theme')
local ui = require('nice-git.ui')

local M = { collapsed = { worktrees = true, prs = true }, rows = {}, header_rows = {} }

local ns = api.nvim_create_namespace('nice-git')
local ns_right = api.nvim_create_namespace('nice-git-right')
local ns_hover = api.nvim_create_namespace('nice-git-hover-line')
local ns_drop = api.nvim_create_namespace('nice-git-drop')

local SECTIONS = {
  { key = 'staged', title = 'STAGED CHANGES' },
  { key = 'changes', title = 'CHANGES' },
  { key = 'untracked', title = 'UNTRACKED' },
}

local STATUS = {
  A = { 'A', 'NiceGitAdded' },
  ['?'] = { 'U', 'NiceGitAdded' },
  M = { 'M', 'NiceGitModified' },
  T = { 'T', 'NiceGitModified' },
  R = { 'R', 'NiceGitModified' },
  C = { 'C', 'NiceGitModified' },
  D = { 'D', 'NiceGitDeleted' },
  U = { '!', 'NiceGitConflict' },
}

local function icons()
  return theme.icons
end

local function state()
  return require('nice-git').state
end

local icon_provider
local function file_icon(path)
  if icon_provider == nil then
    local ok, devicons = pcall(require, 'nvim-web-devicons')
    if _G.MiniIcons then
      icon_provider = function(name)
        return _G.MiniIcons.get('file', name)
      end
    elseif ok then
      icon_provider = function(name)
        return devicons.get_icon(name, nil, { default = true })
      end
    else
      icon_provider = false
    end
  end
  if not icon_provider then
    return icons().file, 'NiceGitDim'
  end
  return icon_provider(vim.fs.basename(path))
end

local function notify_result(ok, out, err)
  if not ok then
    ui.notify(vim.trim(err ~= '' and err or out), vim.log.levels.ERROR)
  end
  require('nice-git').refresh()
end

local function find_win(buf)
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(w) == buf then
      return w
    end
  end
end

---The file list window in the current tab.
function M.win_in_tab()
  return M.buf and find_win(M.buf)
end

function M.header_win_in_tab()
  return M.hbuf and find_win(M.hbuf)
end

---Whether `buf` is one of the panel's own buffers (list, header, commit box).
function M.is_panel_buf(buf)
  return buf == M.buf or buf == M.hbuf or buf == require('nice-git.commit').buf
end

-- Actions ------------------------------------------------------------------------------------

-- Stage or unstage a file row, or a whole section when given a section row.
local function toggle_stage(row)
  local st = state()
  local entries = row.entry and { row.entry } or st.status[row.section]
  if row.section == 'staged' then
    git.unstage(st.root, entries, st.status.has_head, notify_result)
  else
    git.stage(st.root, entries, notify_result)
  end
end

-- Throws away changes of a file row or a whole section; untracked files are deleted.
local function discard(row)
  local st = state()
  local entries = row.entry and { row.entry } or st.status[row.section]
  local what = row.entry and row.entry.path or (#entries .. ' files')
  local untracked = row.section == 'untracked'
  local prompt = untracked and ('Delete ' .. what .. '? This cannot be undone.') or ('Discard changes to ' .. what .. '?')
  if vim.fn.confirm(prompt, '&Discard\n&Cancel', 2) ~= 1 then
    return
  end
  if untracked then
    for _, e in ipairs(entries) do
      os.remove(st.root .. '/' .. e.path)
    end
    vim.cmd.checktime()
    require('nice-git').refresh()
  else
    git.discard(st.root, entries, function(...)
      vim.cmd.checktime()
      notify_result(...)
    end)
  end
end

-- Opens the working file in the editor area (the first window that isn't part of the panel).
local function open_file(row)
  local path = state().root .. '/' .. row.entry.path
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    if not M.is_panel_buf(b) and api.nvim_win_get_config(w).relative == '' and not vim.wo[w].winfixbuf then
      api.nvim_set_current_win(w)
      return vim.cmd.edit(vim.fn.fnameescape(path))
    end
  end
  vim.cmd('botright vsplit ' .. vim.fn.fnameescape(path))
end

local function open_changes(row)
  require('nice-git.diff').open(state(), row)
end

local function file_menu(row)
  local staged = row.section == 'staged'
  local items = {
    { icons().compare, 'Open Changes', open_changes },
    { icons().open_file, 'Open File', open_file },
    { staged and icons().remove or icons().add, staged and 'Unstage Changes' or 'Stage Changes', toggle_stage },
  }
  if not staged then
    table.insert(items, { icons().discard, 'Discard Changes', discard })
  end
  table.insert(items, {
    icons().copy,
    'Copy Relative Path',
    function()
      vim.fn.setreg('+', row.entry.path)
      vim.fn.setreg('"', row.entry.path)
    end,
  })
  ui.select(items, {
    prompt = vim.fs.basename(row.entry.path),
    format_item = function(i)
      return i[2]
    end,
    icon = function(i)
      return i[1]
    end,
  }, function(choice)
    if choice then
      choice[3](row)
    end
  end)
end

-- Rows ---------------------------------------------------------------------------------------
-- A row is a table:
--   text, hls = { {start_col, end_col, group} }, band = true for section title bands
--   right = { item... } right-aligned, each item { chunks = {{text, hl}...}, fn?, tip?, hover? }
--           (`hover` items only show on the hovered row and the cursor row)
--   buttons = { {start_col, end_col, fn, tip?} } clickable byte ranges of `text`
--   click(row), menu(row), section, entry

local function button(icon, tip, fn)
  return { chunks = { { ' ' .. icon .. ' ', 'NiceGitAccent' } }, fn = fn, tip = tip, hover = true }
end

local function width_of(item)
  local w = 0
  for _, c in ipairs(item.chunks) do
    w = w + api.nvim_strwidth(c[1])
  end
  return w
end

-- Which row lines currently show their hover-only items.
local active = { hover = nil, cursor = nil }

---@param force? boolean include hover-only items regardless of hover/cursor
local function visible_right(row, line, force)
  local out = {}
  for _, item in ipairs(row.right or {}) do
    if force or not item.hover or line == active.hover or line == active.cursor then
      table.insert(out, item)
    end
  end
  return out
end

local function draw_right(buf, rows, line)
  local row = rows[line]
  if not row then
    return
  end
  api.nvim_buf_clear_namespace(buf, ns_right, line - 1, line)
  local chunks = {}
  for _, item in ipairs(visible_right(row, line)) do
    vim.list_extend(chunks, item.chunks)
  end
  if #chunks > 0 then
    table.insert(chunks, { ' ', 'NiceGitDim' })
    api.nvim_buf_set_extmark(buf, ns_right, line - 1, 0, {
      virt_text = chunks,
      virt_text_pos = 'right_align',
      hl_mode = 'combine',
    })
  end
end

local function draw(buf, rows)
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return
  end
  local lines = {}
  for i, row in ipairs(rows) do
    lines[i] = row.text
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for _, n in ipairs({ ns, ns_right }) do
    api.nvim_buf_clear_namespace(buf, n, 0, -1)
  end
  for i, row in ipairs(rows) do
    if row.band then
      api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { line_hl_group = 'NiceGitBand', priority = 50 })
    end
    for _, h in ipairs(row.hls or {}) do
      api.nvim_buf_set_extmark(buf, ns, i - 1, h[1], { end_col = h[2], hl_group = h[3], priority = 120 })
    end
    draw_right(buf, rows, i)
  end
end

---What is under the mouse in a row: a right-aligned item, a text button, or nothing. The row
---under the pointer always shows its hover buttons, even if no hover event arrived first.
local function hit(row, line, pos)
  local from_right = api.nvim_win_get_width(pos.winid) - pos.wincol - 1 -- trailing pad cell
  local items = visible_right(row, line, true)
  local acc = 0
  for i = #items, 1, -1 do
    local w = width_of(items[i])
    if from_right >= acc and from_right < acc + w then
      return items[i].fn and items[i]
    end
    acc = acc + w
  end
  for _, b in ipairs(row.buttons or {}) do
    if pos.column > b[1] and pos.column <= b[2] then
      return { fn = b[3], tip = b[4] }
    end
  end
end

-- Header ---------------------------------------------------------------------------------------

local spinner = { frame = 1 }

-- A full-width pill: " ╭ label … │ ▾ ╮ " with the label part and the menu part clickable.
local function commit_button(width, label, on_commit, on_menu)
  local cap_l, cap_r = icons().pill_left, icons().pill_right
  local menu = ' ' .. icons().expanded .. ' '
  local inner = width - 4 - api.nvim_strwidth(menu) - 1 -- margins, caps, menu part, separator
  local lw = api.nvim_strwidth(label)
  local left = math.max(0, math.floor((inner - lw) / 2))
  local main = (' '):rep(left) .. label .. (' '):rep(math.max(0, inner - lw - left))
  local text = ' ' .. cap_l .. main .. '│' .. menu .. cap_r .. ' '
  local a = 1 + #cap_l -- start of main
  local s = a + #main -- separator
  local m = s + #'│' -- menu
  local e = m + #menu -- right cap
  return {
    text = text,
    hls = {
      { 1, a, 'NiceGitPillEdge' },
      { a, e, 'NiceGitPill' },
      { e, e + #cap_r, 'NiceGitPillEdge' },
    },
    buttons = {
      { a, s, function()
        on_commit()
      end, 'Commit' },
      { m, e, on_menu, 'More commit actions' },
    },
  }
end

local function soft_pills(prefix, list)
  local text, hls, buttons = prefix, {}, {}
  for _, p in ipairs(list) do
    text = text .. ' '
    local start = #text
    text = text .. icons().pill_left .. ' ' .. p[1] .. ' ' .. icons().pill_right
    table.insert(hls, { start, start + #icons().pill_left, 'NiceGitPillSoftEdge' })
    table.insert(hls, { start + #icons().pill_left, #text - #icons().pill_right, 'NiceGitPillSoft' })
    table.insert(hls, { #text - #icons().pill_right, #text, 'NiceGitPillSoftEdge' })
    table.insert(buttons, { start, #text, p[2], p[3] })
  end
  return text, hls, buttons
end

local function commit_menu()
  local commit = require('nice-git.commit')
  local actions = require('nice-git.actions')
  local items = {
    { icons().check, 'Commit', commit.commit },
    { icons().edit, 'Commit (Amend)', function()
      commit.commit({ amend = true })
    end },
    { icons().check, 'Commit All (stage everything tracked)', function()
      commit.commit({ all = true })
    end },
    { icons().history, 'Edit Last Commit Message', commit.toggle_amend },
    { icons().stash, 'Stash All Changes', actions.stash },
  }
  ui.select(items, {
    prompt = 'Commit',
    format_item = function(i)
      return i[2]
    end,
    icon = function(i)
      return i[1]
    end,
  }, function(choice)
    if choice then
      choice[3]()
    end
  end)
end

local function build_header(width)
  local st = state().status
  local commit = require('nice-git.commit')
  local actions = require('nice-git.actions')
  local rows = {}
  for _ = 1, commit.height() + 2 do
    table.insert(rows, { text = '' }) -- space under the commit box float
  end

  local label = icons().check .. '  ' .. (commit.amend and 'Amend Commit' or st.operation == 'merge' and 'Commit Merge' or 'Commit')
  table.insert(rows, commit_button(width, label, commit.commit, commit_menu))

  local name = st.branch == '(detached)' and 'detached HEAD' or st.branch or '?'
  local branch = '  ' .. icons().branch .. ' ' .. name
  local text, hls = branch, { { 2, #branch, 'NiceGitAccent' } }
  if actions.busy then
    local status = '  ' .. icons().spinner[spinner.frame] .. ' ' .. actions.busy .. '…'
    table.insert(hls, { #text, #text + #status, 'NiceGitDim' })
    text = text .. status
  elseif st.ahead then
    local counts = ('  %s%d %s%d'):format(icons().pull, st.behind, icons().push, st.ahead)
    table.insert(hls, { #text, #text + #counts, 'NiceGitDim' })
    text = text .. counts
  end
  local function hdr_btn(icon, tip, fn)
    return { chunks = { { ' ' .. icon .. ' ', 'NiceGitDim' } }, fn = fn, tip = tip }
  end
  table.insert(rows, {
    text = text,
    hls = hls,
    buttons = { { 2, #branch, actions.switch_branch, 'Switch branch' } },
    right = {
      hdr_btn(icons().fetch, 'Fetch', actions.fetch),
      hdr_btn(icons().pull, 'Pull', actions.pull),
      hdr_btn(icons().push, 'Push', actions.push),
    },
  })

  if st.operation then
    local ops = { { 'Continue', actions.continue, 'Continue the ' .. st.operation } }
    if st.operation == 'rebase' or st.operation == 'cherry-pick' then
      table.insert(ops, { 'Skip', actions.skip, 'Skip this commit' })
    end
    table.insert(ops, { 'Abort', actions.abort, 'Abort the ' .. st.operation })
    local prefix = '  ' .. icons().warning .. ' ' .. st.operation:upper()
    local t, h, b = soft_pills(prefix, ops)
    table.insert(h, 1, { 0, #prefix, 'NiceGitModified' })
    table.insert(rows, { text = t, hls = h, buttons = b })
  end
  if st.superproject then
    local t = '  ' .. icons().repo .. '  Parent repository'
    table.insert(rows, {
      text = t,
      hls = { { 0, #t, 'NiceGitAccent' } },
      click = function()
        require('nice-git').switch_repo(st.superproject)
      end,
    })
  end
  return rows
end

-- Winbar of the header: title, repo name, and icon buttons.
local PANEL_ACTIONS = {}
_G.NiceGitPanelClick = function(id)
  if PANEL_ACTIONS[id] then
    vim.schedule(PANEL_ACTIONS[id])
  end
end

local function winbar()
  local function b(id, icon)
    return ('%%%d@v:lua.NiceGitPanelClick@ %s %%X'):format(id, icon)
  end
  local repo = vim.fs.basename(state().root or ''):gsub('%%', '%%%%')
  return '%#NiceGitPanelTitle#  SOURCE CONTROL %#NiceGitDim#' .. repo .. '%=%#NiceGitDim#'
    .. b(1, icons().history)
    .. b(2, icons().refresh)
    .. b(3, icons().more)
    .. ' '
end

local function more_menu()
  local actions = require('nice-git.actions')
  local items = {
    { icons().fetch, 'Fetch', actions.fetch },
    { icons().pull, 'Pull', actions.pull },
    { icons().push, 'Push', actions.push },
    { icons().branch, 'Switch Branch…', actions.switch_branch },
    { icons().stash, 'Stash All Changes', actions.stash },
    { icons().split, 'Toggle Inline / Side-by-side Diff', require('nice-git.diff').toggle_mode },
    { icons().circle, 'Hide nice-git (:NiceGit toggle)', require('nice-git').toggle_workspace },
    { icons().close, 'Close Panel', M.close },
  }
  ui.select(items, {
    prompt = 'Source Control',
    format_item = function(i)
      return i[2]
    end,
    icon = function(i)
      return i[1]
    end,
  }, function(choice)
    if choice then
      choice[3]()
    end
  end)
end

PANEL_ACTIONS[1] = function()
  require('nice-git.log').open()
end
PANEL_ACTIONS[2] = function()
  require('nice-git').refresh()
end
PANEL_ACTIONS[3] = more_menu

function M.render_header()
  local hwin = M.header_win_in_tab()
  if not (M.hbuf and api.nvim_buf_is_valid(M.hbuf) and state().status) then
    return
  end
  local width = hwin and api.nvim_win_get_width(hwin) or require('nice-git').config.width
  M.header_rows = build_header(width)
  draw(M.hbuf, M.header_rows)
  for _, w in ipairs(vim.fn.win_findbuf(M.hbuf)) do
    vim.wo[w].winbar = winbar()
    api.nvim_win_set_height(w, #M.header_rows + 1) -- the winbar takes a row of the height
    -- The header never scrolls: the commit box float sits over its first lines.
    api.nvim_win_call(w, function()
      vim.fn.winrestview({ topline = 1 })
    end)
  end
  require('nice-git.commit').layout()

  -- Keep the spinner turning while a remote operation runs.
  local busy = require('nice-git.actions').busy
  if busy and not spinner.timer then
    spinner.timer = assert(vim.uv.new_timer())
    spinner.timer:start(100, 100, vim.schedule_wrap(function()
      spinner.frame = spinner.frame % #icons().spinner + 1
      M.render_header()
    end))
  elseif not busy and spinner.timer then
    spinner.timer:stop()
    spinner.timer:close()
    spinner.timer = nil
  end
end

-- List -----------------------------------------------------------------------------------------

local function build_list()
  local st = state().status
  local actions = require('nice-git.actions')
  local rows = {}
  local function add(row)
    table.insert(rows, row)
    return row
  end

  -- Collapsible band with a title; `fill` adds the rows below it when expanded.
  local function section(key, title, count, right, fill, on_expand)
    local text = ' ' .. (M.collapsed[key] and icons().collapsed or icons().expanded) .. ' ' .. title
    right = vim.list_slice(right or {})
    if count ~= '' then
      local pill = theme.pill(tostring(count), true)
      table.insert(right, { chunks = pill })
    end
    add({
      text = text,
      band = true,
      section = key,
      hls = { { 0, #text, 'NiceGitBand' } },
      right = right,
      click = function()
        M.collapsed[key] = not M.collapsed[key]
        if not M.collapsed[key] and on_expand then
          on_expand()
        end
        M.render()
      end,
    })
    if not M.collapsed[key] then
      fill()
    end
  end

  local any = false
  for _, sec in ipairs(SECTIONS) do
    local entries = st[sec.key]
    if #entries > 0 then
      any = true
      local staged = sec.key == 'staged'
      local stage_btn = staged and button(icons().remove, 'Unstage', toggle_stage) or button(icons().add, 'Stage', toggle_stage)
      local section_right = staged and { button(icons().remove, 'Unstage All', toggle_stage) }
        or { button(icons().discard, 'Discard All', discard), button(icons().add, 'Stage All', toggle_stage) }
      section(sec.key, sec.title, #entries, section_right, function()
        for _, e in ipairs(entries) do
          local icon, icon_hl = file_icon(e.path)
          local name = vim.fs.basename(e.path)
          local dir = vim.fs.dirname(e.path)
          local st_char, st_hl = unpack(STATUS[e.status] or { e.status, 'NiceGitModified' })
          local prefix = '    ' .. icon .. ' '
          local line = prefix .. name .. (dir ~= '.' and '  ' .. dir or '')
          local right = { button(icons().open_file, 'Open File', open_file) }
          if not staged then
            table.insert(right, button(icons().discard, sec.key == 'untracked' and 'Delete File' or 'Discard Changes', discard))
          end
          table.insert(right, stage_btn)
          table.insert(right, { chunks = { { ' ' .. st_char .. ' ', st_hl } } })
          add({
            text = line,
            section = sec.key,
            entry = e,
            hls = {
              { 4, #prefix - 1, icon_hl or 'NiceGitDim' },
              { #prefix, #prefix + #name, st_hl },
              { #prefix + #name, #line, 'NiceGitDim' },
            },
            right = right,
            click = open_changes,
            menu = file_menu,
          })
        end
      end)
    end
  end
  if not any then
    local text = '    ' .. icons().check .. '  No changes'
    add({ text = text, hls = { { 0, #text, 'NiceGitDim' } } })
    add({ text = '' })
  end

  local root = state().root
  local worktrees = st.worktrees or {}
  section('worktrees', 'WORKTREES', #worktrees, { button(icons().add, 'Add Worktree', actions.add_worktree) }, function()
    for i, wt in ipairs(worktrees) do
      local current = wt.path == root
      local name = wt.branch or (wt.bare and '(bare)') or '(detached)'
      local prefix = '    ' .. (current and icons().dot or icons().worktree) .. ' '
      local line = prefix .. name .. '  ' .. vim.fn.fnamemodify(wt.path, ':~')
      add({
        text = line,
        hls = { { 4, #prefix, current and 'NiceGitAdded' or 'NiceGitDim' }, { #prefix + #name, #line, 'NiceGitDim' } },
        -- The first entry is the main worktree, which can't be removed.
        right = (i > 1 and not current) and { button(icons().trash, 'Remove Worktree', function()
          actions.remove_worktree(wt)
        end) } or nil,
        click = not current and function()
          require('nice-git').switch_repo(wt.path)
        end or nil,
      })
    end
  end)

  local submodules = st.submodules or {}
  if #submodules > 0 then
    section('submodules', 'SUBMODULES', #submodules, nil, function()
      for _, sm in ipairs(submodules) do
        local prefix = '    ' .. icons().repo .. ' '
        local line = prefix .. sm.path .. (sm.state ~= 'ok' and '  ' .. sm.state or '')
        add({
          text = line,
          hls = { { 4, #prefix, 'NiceGitDim' }, { #prefix + #sm.path, #line, sm.state == 'ok' and 'NiceGitDim' or 'NiceGitModified' } },
          right = { button(icons().refresh, 'Update Submodule', function()
            actions.update_submodule(sm)
          end) },
          click = function()
            require('nice-git').switch_repo(root .. '/' .. sm.path)
          end,
        })
      end
    end)
  end

  local github = require('nice-git.github')
  if github.available() then
    local prs = github.prs.root == root and github.prs or {}
    local right = { button(icons().pr_create, 'Create Pull Request', github.create), button(icons().refresh, 'Reload', github.load) }
    section('prs', 'PULL REQUESTS', prs.list and #prs.list or '', right, function()
      local function note(text, hl)
        add({ text = '    ' .. text, hls = { { 0, 4 + #text, hl } } })
      end
      if prs.loading then
        note(icons().spinner[1] .. ' Loading…', 'NiceGitDim')
      elseif prs.error then
        note(icons().error .. ' ' .. prs.error:gsub('\n.*', ''), 'NiceGitConflict')
      elseif prs.list and #prs.list == 0 then
        note('No open pull requests', 'NiceGitDim')
      end
      for _, pr in ipairs(prs.list or {}) do
        local prefix = '    ' .. icons().pr .. ' '
        local num = '#' .. pr.number
        local line = prefix .. num .. ' ' .. pr.title
        local hls = { { 4, #prefix, pr.isDraft and 'NiceGitDim' or 'NiceGitAdded' }, { #prefix, #prefix + #num, 'NiceGitDim' } }
        if pr.isDraft then
          table.insert(hls, { #prefix + #num, #line, 'NiceGitDim' })
        end
        add({
          text = line,
          hls = hls,
          right = {
            button(icons().external, 'Open in Browser', function()
              github.browse(pr)
            end),
            { chunks = { { (pr.author and pr.author.login or '') .. ' ', 'NiceGitDim' } } },
          },
          click = function()
            github.menu(pr)
          end,
          menu = function()
            github.menu(pr)
          end,
        })
      end
    end, github.ensure_loaded)
  end

  local stashes = st.stashes or {}
  if #stashes > 0 then
    section('stashes', 'STASHES', #stashes, nil, function()
      for _, stash in ipairs(stashes) do
        local prefix = '    ' .. icons().stash .. ' '
        local line = prefix .. stash.message
        add({
          text = line,
          stash = stash,
          hls = { { 4, #prefix, 'NiceGitDim' } },
          right = {
            button(icons().pull, 'Apply Stash', function()
              actions.stash_apply(stash)
            end),
            button(icons().close, 'Drop Stash', function()
              actions.stash_drop(stash)
            end),
          },
          click = function()
            actions.show_stash(stash)
          end,
        })
      end
    end)
  end
  return rows
end

function M.render()
  if not (M.buf and api.nvim_buf_is_valid(M.buf) and state().status) then
    return
  end
  M.rows = build_list()
  active.hover = nil
  api.nvim_buf_clear_namespace(M.buf, ns_hover, 0, -1)
  draw(M.buf, M.rows)
  M.render_header()
  require('nice-git.commit').update_placeholder()
end

-- Mouse ----------------------------------------------------------------------------------------

local function set_active(key, line)
  if active[key] == line then
    return
  end
  local old = active[key]
  active[key] = line
  if key == 'hover' then
    api.nvim_buf_clear_namespace(M.buf, ns_hover, 0, -1)
    if line and M.rows[line] and (M.rows[line].click or M.rows[line].entry) then
      api.nvim_buf_set_extmark(M.buf, ns_hover, line - 1, 0, { line_hl_group = 'NiceGitHover', priority = 60 })
    end
  end
  if old then
    draw_right(M.buf, M.rows, old)
  end
  if line then
    draw_right(M.buf, M.rows, line)
  end
end

-- Dropping onto the other side of the staged/unstaged divide is the only meaningful move.
local function crosses(from, to)
  return to and to.section and (from.section == 'staged') ~= (to.section == 'staged')
end

local function show_drop_target(row, target)
  api.nvim_buf_clear_namespace(M.buf, ns_drop, 0, -1)
  if not (row and crosses(row, target)) then
    return
  end
  for l, r in ipairs(M.rows) do
    if r.section == target.section then
      api.nvim_buf_set_extmark(M.buf, ns_drop, l - 1, 0, { line_hl_group = 'NiceGitDropTarget', priority = 70 })
    end
  end
end

local function click_in(rows)
  return function(pos)
    local row = rows()[pos.line]
    if not row then
      return
    end
    local target = hit(row, pos.line, pos)
    if target then
      target.fn(row)
    elseif row.click then
      row.click(row)
    end
  end
end

local function cursor_row()
  return M.rows[api.nvim_win_get_cursor(0)[1]]
end

local function setup_list_buf(buf)
  ui.clickable(buf, {
    click = click_in(function()
      return M.rows
    end),
    draggable = function(pos)
      local row = M.rows[pos.line]
      return row and row.entry and row
    end,
    dragging = function(row, pos)
      show_drop_target(row, row and M.rows[pos.line])
    end,
    drop = function(row, pos)
      if crosses(row, M.rows[pos.line]) then
        toggle_stage(row)
      end
    end,
    right_click = function(pos)
      local row = M.rows[pos.line]
      if row and row.menu then
        row.menu(row)
      end
    end,
  })
  ui.on_hover(buf, function(pos)
    set_active('hover', pos and pos.line)
    local row = pos and M.rows[pos.line]
    local target = row and hit(row, pos.line, pos)
    return target and target.tip
  end)
  api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = function()
      set_active('cursor', api.nvim_win_get_cursor(0)[1])
    end,
  })

  local function map(lhs, rhs, desc)
    vim.keymap.set('n', lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  local function with_row(fn)
    return function()
      local row = cursor_row()
      if row then
        fn(row)
      end
    end
  end
  map('<CR>', with_row(function(row)
    if row.click then
      row.click(row)
    end
  end), 'Open changes / toggle section')
  map('-', with_row(function(row)
    if row.section and (row.entry or row.band) then
      toggle_stage(row)
    end
  end), 'Stage / unstage')
  map('x', with_row(function(row)
    if row.section and row.section ~= 'staged' and (row.entry or row.band) then
      discard(row)
    end
  end), 'Discard changes')
  map('o', with_row(function(row)
    if row.entry then
      open_file(row)
    end
  end), 'Open file')
  map('m', with_row(function(row)
    if row.menu then
      row.menu(row)
    end
  end), 'Menu')
end

-- Keys shared by the list and the header.
local function setup_common_keys(buf)
  local actions = require('nice-git.actions')
  local function map(lhs, rhs, desc)
    vim.keymap.set('n', lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map('b', actions.switch_branch, 'Switch branch')
  map('l', require('nice-git.log').open, 'History')
  map('f', actions.fetch, 'Fetch')
  map('p', actions.pull, 'Pull')
  map('P', actions.push, 'Push')
  map('c', function()
    require('nice-git.commit').focus()
  end, 'Write commit message')
  map('R', function()
    require('nice-git').refresh()
  end, 'Refresh')
  map('q', M.close, 'Close panel')
end

local function new_buf(name)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, name)
  vim.bo[buf].filetype = 'nice-git'
  vim.bo[buf].modifiable = false
  return buf
end

local function ensure_bufs()
  if not (M.buf and api.nvim_buf_is_valid(M.buf)) then
    M.buf = new_buf('nice-git://status')
    setup_list_buf(M.buf)
    setup_common_keys(M.buf)
    -- Watch the repo only while the panel is visible somewhere.
    api.nvim_create_autocmd('BufWinEnter', {
      buffer = M.buf,
      callback = function()
        require('nice-git').watch()
      end,
    })
    api.nvim_create_autocmd('BufWinLeave', {
      buffer = M.buf,
      callback = function()
        require('nice-git').unwatch()
      end,
    })
  end
  if not (M.hbuf and api.nvim_buf_is_valid(M.hbuf)) then
    M.hbuf = new_buf('nice-git://header')
    ui.clickable(M.hbuf, {
      click = click_in(function()
        return M.header_rows
      end),
    })
    ui.on_hover(M.hbuf, function(pos)
      local row = pos and M.header_rows[pos.line]
      local target = row and hit(row, pos.line, pos)
      return target and target.tip
    end)
    setup_common_keys(M.hbuf)
  end
end

local function style(win)
  theme.style_window(win, 'panel')
  local wo = vim.wo[win]
  wo.wrap, wo.winfixwidth, wo.winfixbuf = false, true, true
end

---Opens the panel as a full-height column (right or left, per config) in the current tab and
---returns the list window.
function M.open_win()
  ensure_bufs()
  local list = M.win_in_tab()
  if not list then
    local config = require('nice-git').config
    local side = config.position == 'left' and 'left' or 'right'
    list = api.nvim_open_win(M.buf, true, { split = side, win = -1, width = config.width })
    style(list)
    vim.wo[list].cursorline = true
  end
  local header = M.header_win_in_tab()
  if not header then
    header = api.nvim_open_win(M.hbuf, false, { split = 'above', win = list, height = math.max(#M.header_rows + 1, 7) })
    style(header)
    vim.wo[header].winfixheight = true
  end
  require('nice-git.commit').open_win(header)
  if state().status then
    M.render()
  else
    require('nice-git').refresh()
  end
  return list
end

---Whether the panel is open in `tab`.
function M.visible_in(tab)
  for _, w in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if api.nvim_win_get_buf(w) == M.buf then
      return true
    end
  end
  return false
end

---Closes the panel in any tab, not just the current one.
function M.close_in(tab)
  -- The commit box float first: it is pinned to the header window.
  local order = { require('nice-git.commit').buf, M.hbuf, M.buf }
  for _, buf in ipairs(order) do
    for _, w in ipairs(buf and api.nvim_tabpage_list_wins(tab) or {}) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_buf(w) == buf then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end
end

function M.close()
  local commit_win = require('nice-git.commit').win_in_tab()
  if commit_win then
    pcall(api.nvim_win_close, commit_win, true)
  end
  local header = M.header_win_in_tab()
  if header then
    pcall(api.nvim_win_close, header, false)
  end
  local win = M.win_in_tab()
  if win and not pcall(api.nvim_win_close, win, false) then
    ui.notify('cannot close the last window', vim.log.levels.WARN)
  end
end

-- Keep the header (full-width Commit button) and commit box fitted to the panel width.
api.nvim_create_autocmd('WinResized', {
  group = api.nvim_create_augroup('NiceGitPanelResize', {}),
  callback = function()
    for _, w in ipairs(vim.v.event.windows or {}) do
      if api.nvim_win_is_valid(w) and M.is_panel_buf(api.nvim_win_get_buf(w)) then
        return M.render_header()
      end
    end
  end,
})

return M
