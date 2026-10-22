-- Visual system: colors derived from the active colorscheme, highlight groups, icons, and window
-- styling that hides Vim chrome in plugin windows.
local api = vim.api

local M = {}

-- Codicons (VSCode's icon font) as shipped in Nerd Fonts; override any with setup({ icons = {...} }).
M.icons = {
  add = '\u{ea60}',
  remove = '\u{eb3b}',
  check = '\u{eab2}',
  close = '\u{ea76}',
  discard = '\u{eae2}',
  refresh = '\u{eb37}',
  sync = '\u{ea77}',
  push = '\u{eaa1}',
  pull = '\u{ea9a}',
  fetch = '\u{eac2}',
  history = '\u{ea82}',
  branch = '\u{ea68}',
  commit = '\u{eafc}',
  merge = '\u{eafe}',
  pr = '\u{ea64}',
  pr_create = '\u{ebbc}',
  repo = '\u{ea62}',
  worktree = '\u{ea63}',
  expanded = '\u{eab4}',
  collapsed = '\u{eab6}',
  file = '\u{ea7b}',
  open_file = '\u{ea94}',
  warning = '\u{ea6c}',
  stash = '\u{ea98}',
  copy = '\u{ebcc}',
  split = '\u{eb56}',
  inline = '\u{eae1}',
  more = '\u{ea7c}',
  dot = '\u{ea71}',
  circle = '\u{eabc}',
  tag = '\u{ea66}',
  edit = '\u{ea73}',
  trash = '\u{ea81}',
  external = '\u{eb14}',
  gripper = '\u{eb04}',
  ok = '\u{eba4}',
  error = '\u{ea87}',
  info = '\u{ea74}',
  compare = '\u{eafd}',
  graph = '\u{eb03}',
  prev = '\u{eaa1}',
  next = '\u{ea9a}',
  -- Rounded half-circle caps that turn a colored span into a pill.
  pill_left = '\u{e0b6}',
  pill_right = '\u{e0b4}',
  spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' },
}

local function rgb(n)
  return { math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256 }
end

---Mixes color `a` toward `b` by `t` (0..1); both are 24-bit integers.
local function blend(a, b, t)
  local x, y = rgb(a), rgb(b)
  local out = 0
  for i = 1, 3 do
    out = out * 256 + math.floor(x[i] + (y[i] - x[i]) * t + 0.5)
  end
  return out
end
M.blend = blend

local function get(name, attr)
  local hl = api.nvim_get_hl(0, { name = name, link = false })
  return hl[attr]
end

local function first(attr, names, fallback)
  for _, name in ipairs(names) do
    local v = get(name, attr)
    if v then
      return v
    end
  end
  return fallback
end

-- Groups used when colors can't be computed (no 'termguicolors'): plain links.
local LINKS = {
  NiceGitPanel = 'NormalFloat',
  NiceGitPanelTitle = 'Title',
  NiceGitPanelEob = 'EndOfBuffer',
  NiceGitBand = 'CursorLine',
  NiceGitHover = 'CursorLine',
  NiceGitSelected = 'Visual',
  NiceGitSeparator = 'WinSeparator',
  NiceGitBorder = 'FloatBorder',
  NiceGitBorderTitle = 'FloatTitle',
  NiceGitInput = 'Normal',
  NiceGitAccent = 'Function',
  NiceGitDim = 'Comment',
  NiceGitPill = 'PmenuSel',
  NiceGitPillEdge = 'Function',
  NiceGitPillSoft = 'Pmenu',
  NiceGitPillSoftEdge = 'Comment',
  NiceGitAdded = 'Added',
  NiceGitModified = 'Changed',
  NiceGitDeleted = 'Removed',
  NiceGitConflict = 'DiagnosticError',
  NiceGitDiffAdd = 'DiffAdd',
  NiceGitDiffAddText = 'DiffText',
  NiceGitDiffDelete = 'DiffDelete',
  NiceGitDiffDeleteText = 'DiffText',
  NiceGitDiffFiller = 'NonText',
  NiceGitToolbar = 'WinBar',
  NiceGitToolbarTitle = 'WinBar',
  NiceGitToast = 'NormalFloat',
}

-- Names the views use, mapped onto the palette groups above.
local ALIASES = {
  NiceGitHeader = 'NiceGitPanelTitle',
  NiceGitSection = 'NiceGitBand',
  NiceGitCount = 'NiceGitDim',
  NiceGitPath = 'NiceGitDim',
  NiceGitEmpty = 'NiceGitDim',
  NiceGitPlaceholder = 'NiceGitDim',
  NiceGitButton = 'NiceGitAccent',
  NiceGitCommitButton = 'NiceGitPill',
  NiceGitDropTarget = 'NiceGitSelected',
  NiceGitInlineAdd = 'NiceGitDiffAdd',
  NiceGitInlineDelete = 'NiceGitDiffDelete',
  NiceGitToolbarButton = 'NiceGitPillSoft',
  NiceGitConflictOurs = 'NiceGitDiffAdd',
  NiceGitConflictTheirs = 'NiceGitDiffChange',
  NiceGitConflictBase = 'NiceGitBand',
  NiceGitConflictMarker = 'NiceGitDim',
  NiceGitConflictButton = 'NiceGitPill',
  NiceGitOperation = 'NiceGitModified',
  NiceGitHash = 'NiceGitAccent',
  NiceGitRef = 'NiceGitModified',
  NiceGitBlame = 'NiceGitDim',
}

local GRAPH = { 'Function', 'String', 'Keyword', 'Type', 'Constant', 'Identifier' }

function M.apply()
  -- Computed groups are re-derived on every theme change; aliases stay overridable by the user.
  local set = function(name, spec)
    api.nvim_set_hl(0, name, spec)
  end
  for name, target in pairs(ALIASES) do
    api.nvim_set_hl(0, name, { link = target, default = true })
  end
  if not vim.o.termguicolors then
    for name, target in pairs(LINKS) do
      set(name, { link = target })
    end
    for i, g in ipairs(GRAPH) do
      set('NiceGitGraph' .. i, { link = g })
    end
    set('NiceGitDiffChange', { link = 'DiffChange' })
    return
  end

  local dark = vim.o.background == 'dark'
  local bg = get('Normal', 'bg') or (dark and 0x1e1e1e or 0xffffff)
  local fg = get('Normal', 'fg') or (dark and 0xd4d4d4 or 0x1f1f1f)
  local accent = first('fg', { 'Function', 'Special', 'Title' }, dark and 0x3794ff or 0x005fb8)
  local green = first('fg', { 'Added', 'diffAdded', 'String' }, dark and 0x73c991 or 0x388a34)
  local yellow = first('fg', { 'Changed', 'diffChanged', 'WarningMsg' }, dark and 0xe2c08d or 0x895503)
  local red = first('fg', { 'Removed', 'diffRemoved', 'ErrorMsg' }, dark and 0xe4676b or 0xad0707)

  local panel = blend(bg, fg, 0.04)
  local band = blend(bg, fg, 0.09)
  local soft = blend(bg, fg, 0.16)
  local dim = blend(fg, panel, 0.45)

  set('NiceGitPanel', { fg = fg, bg = panel })
  set('NiceGitPanelTitle', { fg = dim, bg = panel, bold = true })
  set('NiceGitPanelEob', { fg = panel, bg = panel })
  set('NiceGitBand', { fg = fg, bg = band, bold = true })
  set('NiceGitHover', { bg = blend(bg, fg, 0.13) })
  set('NiceGitSelected', { bg = blend(panel, accent, 0.25) })
  set('NiceGitSeparator', { fg = band, bg = bg })
  set('NiceGitBorder', { fg = blend(bg, fg, 0.3), bg = panel })
  set('NiceGitBorderTitle', { fg = fg, bg = panel, bold = true })
  set('NiceGitInput', { fg = fg, bg = bg })
  set('NiceGitInputBorder', { fg = blend(bg, accent, 0.6), bg = bg })
  set('NiceGitAccent', { fg = accent })
  set('NiceGitDim', { fg = dim })
  -- Pills: the body has a background; the caps only a foreground, so they take the row's color.
  set('NiceGitPill', { fg = bg, bg = accent, bold = true })
  set('NiceGitPillEdge', { fg = accent })
  set('NiceGitPillSoft', { fg = fg, bg = soft })
  set('NiceGitPillSoftEdge', { fg = soft })
  set('NiceGitAdded', { fg = green })
  set('NiceGitModified', { fg = yellow })
  set('NiceGitDeleted', { fg = red, strikethrough = true })
  set('NiceGitConflict', { fg = red, bold = true })
  set('NiceGitDiffAdd', { bg = blend(bg, green, 0.15) })
  set('NiceGitDiffAddText', { bg = blend(bg, green, 0.35) })
  set('NiceGitDiffDelete', { bg = blend(bg, red, 0.15) })
  set('NiceGitDiffDeleteText', { bg = blend(bg, red, 0.35) })
  set('NiceGitDiffChange', { bg = blend(bg, yellow, 0.12) })
  set('NiceGitDiffFiller', { fg = blend(bg, fg, 0.15), bg = bg })
  set('NiceGitGutterAdd', { fg = green })
  set('NiceGitGutterDelete', { fg = red })
  set('NiceGitGutterChange', { fg = yellow })
  set('NiceGitToolbar', { fg = dim, bg = panel })
  set('NiceGitToolbarTitle', { fg = fg, bg = panel, bold = true })
  set('NiceGitToast', { fg = fg, bg = band })
  set('NiceGitToastBorder', { fg = blend(bg, fg, 0.3), bg = band })
  for i, g in ipairs(GRAPH) do
    set('NiceGitGraph' .. i, { fg = get(g, 'fg') or accent })
  end
  set('NiceGitHiddenCursor', { blend = 100, nocombine = true, reverse = true })
end

local WINHL = {
  panel = {
    Normal = 'NiceGitPanel',
    NormalNC = 'NiceGitPanel',
    EndOfBuffer = 'NiceGitPanelEob',
    CursorLine = 'NiceGitSelected',
    WinBar = 'NiceGitPanelTitle',
    WinBarNC = 'NiceGitPanelTitle',
    SignColumn = 'NiceGitPanel',
    WinSeparator = 'NiceGitSeparator',
    StatusLine = 'NiceGitPanel',
    StatusLineNC = 'NiceGitPanel',
  },
  -- Old side: lines only it has were removed, so its "added" lines are red.
  diff_old = {
    DiffAdd = 'NiceGitDiffDelete',
    DiffChange = 'NiceGitDiffDelete',
    DiffText = 'NiceGitDiffDeleteText',
    DiffDelete = 'NiceGitDiffFiller',
    EndOfBuffer = 'NiceGitDiffFiller',
    WinBar = 'NiceGitToolbar',
    WinBarNC = 'NiceGitToolbar',
  },
  diff_new = {
    DiffAdd = 'NiceGitDiffAdd',
    DiffChange = 'NiceGitDiffAdd',
    DiffText = 'NiceGitDiffAddText',
    DiffDelete = 'NiceGitDiffFiller',
    EndOfBuffer = 'NiceGitDiffFiller',
    WinBar = 'NiceGitToolbar',
    WinBarNC = 'NiceGitToolbar',
  },
  page = {
    EndOfBuffer = 'NiceGitDiffFiller',
    WinBar = 'NiceGitToolbar',
    WinBarNC = 'NiceGitToolbar',
  },
  float = {
    Normal = 'NiceGitPanel',
    NormalFloat = 'NiceGitPanel',
    FloatBorder = 'NiceGitBorder',
    FloatTitle = 'NiceGitBorderTitle',
    FloatFooter = 'NiceGitDim',
    CursorLine = 'NiceGitHover',
    EndOfBuffer = 'NiceGitPanelEob',
  },
  input = {
    Normal = 'NiceGitInput',
    NormalFloat = 'NiceGitInput',
    FloatBorder = 'NiceGitInputBorder',
    FloatTitle = 'NiceGitBorderTitle',
    EndOfBuffer = 'NiceGitInput',
  },
  toast = {
    Normal = 'NiceGitToast',
    NormalFloat = 'NiceGitToast',
    FloatBorder = 'NiceGitToastBorder',
  },
}

-- Window kinds that hide the cursor while focused (the cursorline shows the selection instead).
local CURSORLESS = { panel = true, float = true }

---Applies colors and chrome for a kind of window: panel, diff_old, diff_new, page, float, input, toast.
function M.style_window(win, kind)
  local parts = {}
  for from, to in pairs(WINHL[kind]) do
    table.insert(parts, from .. ':' .. to)
  end
  local wo = vim.wo[win]
  wo.winhighlight = table.concat(parts, ',')
  wo.fillchars = kind:match('^diff') and 'eob: ,diff:╱' or 'eob: '
  if kind ~= 'diff_old' and kind ~= 'diff_new' and kind ~= 'page' then
    wo.number, wo.relativenumber, wo.spell, wo.list = false, false, false, false
    wo.signcolumn, wo.foldcolumn, wo.statuscolumn = 'no', '0', ''
  end
  vim.w[win].nice_git_cursorless = CURSORLESS[kind] or nil
end

local saved_guicursor

-- Hides the terminal cursor while a cursorless nice-git window has focus.
local function update_cursor()
  local hide = vim.w.nice_git_cursorless and vim.fn.mode() ~= 'c' and vim.fn.mode() ~= 'i'
  if hide and not saved_guicursor then
    saved_guicursor = vim.o.guicursor
    vim.o.guicursor = 'a:NiceGitHiddenCursor'
  elseif not hide and saved_guicursor then
    vim.o.guicursor = saved_guicursor
    saved_guicursor = nil
  end
end

local group = api.nvim_create_augroup('NiceGitTheme', {})
api.nvim_create_autocmd('ColorScheme', { group = group, callback = M.apply })
api.nvim_create_autocmd('OptionSet', { group = group, pattern = { 'background', 'termguicolors' }, callback = M.apply })
api.nvim_create_autocmd({ 'WinEnter', 'BufEnter', 'CmdlineEnter', 'CmdlineLeave', 'ModeChanged' }, {
  group = group,
  callback = function()
    vim.schedule(update_cursor)
  end,
})
M.apply()

---Chunks for a pill-shaped label; `soft` uses the neutral style instead of the accent color.
function M.pill(text, soft)
  local body = soft and 'NiceGitPillSoft' or 'NiceGitPill'
  return {
    { M.icons.pill_left, body .. 'Edge' },
    { ' ' .. text .. ' ', body },
    { M.icons.pill_right, body .. 'Edge' },
  }
end

return M
