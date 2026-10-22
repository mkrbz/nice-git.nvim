-- Blame for file buffers: end-of-line text on the cursor line, and a scroll-synced side panel.
local api = vim.api
local git = require('nice-git.git')

local M = { line_enabled = false }

local ns = api.nvim_create_namespace('nice-git-blame')
local line_group = api.nvim_create_augroup('NiceGitBlameLine', {})
local panel_group = api.nvim_create_augroup('NiceGitBlamePanel', {})

local UNCOMMITTED = ('0'):rep(40)

-- buf -> { lines = { [line] = sha }, commits = { [sha] = {author, time, summary} }, tick }
local cache = {}

local relative = require('nice-git.ui').ago

local function parse(out)
  local lines, commits, sha = {}, {}, nil
  for _, l in ipairs(vim.split(out, '\n', { plain = true })) do
    local h, final = l:match('^(%x+) %d+ (%d+)')
    if h and #h == 40 then
      sha = h
      lines[tonumber(final)] = sha
      commits[sha] = commits[sha] or {}
    elseif sha and l:sub(1, 1) ~= '\t' then
      local key, val = l:match('^(%S+) (.*)$')
      if key == 'author' then
        commits[sha].author = val
      elseif key == 'author-time' then
        commits[sha].time = tonumber(val)
      elseif key == 'summary' then
        commits[sha].summary = val
      end
    end
  end
  return { lines = lines, commits = commits }
end

local function file_of(buf)
  local name = api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' or name == '' or not vim.uv.fs_stat(name) then
    return nil
  end
  return name
end

---Blames the buffer's current contents (unsaved edits included); cb gets the result.
local function load(buf, cb)
  local file = file_of(buf)
  if not file then
    return
  end
  local tick = api.nvim_buf_get_changedtick(buf)
  if cache[buf] and cache[buf].tick == tick then
    return cb(cache[buf])
  end
  local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'
  local args = { 'blame', '--porcelain', '--contents', '-', '--', vim.fs.basename(file) }
  git.run(vim.fs.dirname(file), args, function(ok, out)
    if not ok or not api.nvim_buf_is_valid(buf) then
      return
    end
    local data = parse(out)
    data.tick = tick
    data.dir = vim.fs.dirname(file)
    cache[buf] = data
    cb(data)
  end, { stdin = text })
end

local function describe(data, line)
  local sha = data.lines[line]
  local c = sha and data.commits[sha]
  if not c then
    return nil
  end
  if sha == UNCOMMITTED then
    return 'You · Uncommitted changes'
  end
  return ('%s, %s · %s'):format(c.author or '?', c.time and relative(c.time) or '?', c.summary or '')
end

-- Line blame ---------------------------------------------------------------------------------

local function show_line()
  local buf = api.nvim_get_current_buf()
  for b in pairs(cache) do
    if api.nvim_buf_is_valid(b) then
      api.nvim_buf_clear_namespace(b, ns, 0, -1)
    end
  end
  if not file_of(buf) then
    return
  end
  local line = api.nvim_win_get_cursor(0)[1]
  load(buf, function(data)
    if api.nvim_get_current_buf() ~= buf or api.nvim_win_get_cursor(0)[1] ~= line then
      return
    end
    local text = describe(data, line)
    if text then
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
        virt_text = { { '    ' .. text, 'NiceGitBlame' } },
        virt_text_pos = 'eol',
        hl_mode = 'combine',
      })
    end
  end)
end

local timer = assert(vim.uv.new_timer())

function M.toggle_line()
  M.line_enabled = not M.line_enabled
  api.nvim_clear_autocmds({ group = line_group })
  if not M.line_enabled then
    for b in pairs(cache) do
      if api.nvim_buf_is_valid(b) then
        api.nvim_buf_clear_namespace(b, ns, 0, -1)
      end
    end
    return
  end
  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufEnter', 'BufWritePost' }, {
    group = line_group,
    callback = function()
      -- Wait for the cursor to settle so scrolling doesn't spawn a blame per line.
      timer:stop()
      timer:start(150, 0, vim.schedule_wrap(show_line))
    end,
  })
  show_line()
end

-- Blame panel --------------------------------------------------------------------------------

local panel -- { buf, win, src_buf, src_win, shas }

local function render_panel()
  if not (panel and api.nvim_buf_is_valid(panel.buf) and api.nvim_buf_is_valid(panel.src_buf)) then
    return
  end
  load(panel.src_buf, function(data)
    if not panel then
      return
    end
    local lines, hls, shas = {}, {}, {}
    local count = api.nvim_buf_line_count(panel.src_buf)
    local prev
    for l = 1, count do
      local sha = data.lines[l]
      shas[l] = sha
      local c = sha and data.commits[sha] or {}
      if sha == prev then
        lines[l] = '         │'
        hls[l] = { { 0, #lines[l], 'NiceGitDim' } }
      elseif sha == UNCOMMITTED then
        lines[l] = 'Uncommitted'
        hls[l] = { { 0, #lines[l], 'NiceGitModified' } }
      else
        -- Columns: hash, author (fixed width), age; changes from the last week stand out.
        local short = (sha or '?'):sub(1, 7)
        local author = vim.fn.strcharpart(c.author or '?', 0, 14)
        author = author .. (' '):rep(15 - api.nvim_strwidth(author))
        local age = c.time and relative(c.time) or '?'
        lines[l] = short .. '  ' .. author .. age
        local recent = c.time and os.time() - c.time < 7 * 86400
        hls[l] = {
          { 0, #short, 'NiceGitAccent' },
          { #short + 2 + #author, #lines[l], recent and 'NiceGitModified' or 'NiceGitDim' },
        }
      end
      prev = sha
    end
    panel.shas = shas
    vim.bo[panel.buf].modifiable = true
    api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
    vim.bo[panel.buf].modifiable = false
    api.nvim_buf_clear_namespace(panel.buf, ns, 0, -1)
    for l, list in pairs(hls) do
      for _, h in ipairs(list) do
        api.nvim_buf_set_extmark(panel.buf, ns, l - 1, h[1], { end_col = h[2], hl_group = h[3] })
      end
    end
    if api.nvim_win_is_valid(panel.win) and api.nvim_win_is_valid(panel.src_win) then
      api.nvim_win_call(panel.src_win, function()
        vim.cmd('syncbind')
      end)
    end
  end)
end

function M.close_panel()
  local p = panel
  panel = nil
  api.nvim_clear_autocmds({ group = panel_group })
  if not p then
    return
  end
  if api.nvim_win_is_valid(p.src_win) then
    vim.wo[p.src_win].scrollbind, vim.wo[p.src_win].cursorbind = false, false
  end
  if api.nvim_win_is_valid(p.win) then
    api.nvim_win_close(p.win, true)
  end
end

local function open_commit_at(line)
  local sha = panel and panel.shas and panel.shas[line]
  if sha and sha ~= UNCOMMITTED then
    require('nice-git.log').show_commit(sha:sub(1, 12), cache[panel.src_buf].dir)
  end
end

---Toggles the blame panel beside the current file window.
function M.toggle_panel()
  if panel then
    return M.close_panel()
  end
  local src_win, src_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  if not file_of(src_buf) then
    return require('nice-git.ui').notify('blame needs a file on disk', vim.log.levels.WARN)
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'nice-git-blame'
  local win = api.nvim_open_win(buf, false, { split = 'left', win = src_win, width = 40 })
  require('nice-git.theme').style_window(win, 'panel')
  local wo = vim.wo[win]
  wo.wrap, wo.winfixwidth, wo.winfixbuf, wo.foldenable = false, true, true, false
  for _, w in ipairs({ win, src_win }) do
    vim.wo[w].scrollbind, vim.wo[w].cursorbind = true, true
  end
  panel = { buf = buf, win = win, src_buf = src_buf, src_win = src_win }

  local function map(lhs, fn)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  for _, n in ipairs({ '', '2-', '3-', '4-' }) do
    map('<' .. n .. 'LeftRelease>', function()
      local pos = vim.fn.getmousepos()
      if pos.winid == win and pos.line > 0 then
        open_commit_at(pos.line)
      end
    end)
  end
  map('<CR>', function()
    open_commit_at(api.nvim_win_get_cursor(0)[1])
  end)
  map('q', M.close_panel)

  api.nvim_create_autocmd({ 'BufWritePost', 'TextChanged', 'InsertLeave' }, {
    group = panel_group,
    buffer = src_buf,
    callback = render_panel,
  })
  api.nvim_create_autocmd('WinClosed', {
    group = panel_group,
    callback = function(ev)
      local closed = tonumber(ev.match)
      if panel and (closed == panel.win or closed == panel.src_win) then
        vim.schedule(M.close_panel)
      end
    end,
  })
  render_panel()
end

return M
