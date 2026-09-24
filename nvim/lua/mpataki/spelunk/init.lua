-- Spelunk: frontier bookkeeping for a code dive. LSP navigation (call
-- hierarchy, references, definitions, the jumps that follow) is recorded as a
-- graph — where you are, what you explored, what the LSP named that you have
-- not visited yet — shown as a tree in a right split and exported as markdown.
-- Glue only: lsp.lua emits events, graph.lua holds the dive, render.lua draws.
--
-- Usage: just navigate. The first gr/gd/incoming/outgoing call with no session
-- starts one rooted at the symbol the question was about.
--   :SpelunkStart [name]  new session rooted at the symbol under the cursor;
--                         name defaults to <root>-<HHMM>. Replaces an open
--                         session (its export stays on disk)
--   :SpelunkStop          end the session and close the split
--   :SpelunkOpen          toggle the tree split (right, 40 cols)
--   :SpelunkNote [text]   one-line note on the current node; prompts without text
--   :SpelunkMark          record the cursor's symbol as a visit (scrolling into an
--                         unknown symbol in the same file is not one on its own)
--   :SpelunkExport        write the export now (it is also written on every change)
--
-- In the split:
--   <CR>  jump to the node in the window you came from
--   n     note on the node under the cursor (the current node on other lines)
--   p     prune / unprune the node under the cursor
--   r     re-render
--   q     close
--
-- Exports live in <git-common-dir>/spelunk/<session>.md (outside the worktree,
-- like review drafts); setup({ export_dir = ... }) points them elsewhere, e.g.
-- the vault, where Obsidian renders the mermaid block live.
--
-- No global keymaps yet; <leader>s* is the suggested prefix once a real dive
-- shows which of these get used.
-- graph and render load on first session, not at startup: the config calls
-- setup() on every launch and most launches never dive. lsp_probe also holds
-- lsp.lua to being usable with graph.lua never loaded.
local function graph() return require('mpataki.spelunk.graph') end
local function render() return require('mpataki.spelunk.render') end
local lsp = require('mpataki.spelunk.lsp')
local pr = require('mpataki.review.pr')

local M = {}

M.WIDTH = 40

local config = {}

-- { g, name, dir, write_failed }. `dir` is the export directory, fixed at start.
local session

-- The split: { win, buf, index } while open.
local split = {}

local function notify(msg, level)
  vim.notify('spelunk: ' .. msg, level or vim.log.levels.INFO)
end

local function sanitize(name)
  local s = vim.trim(name or ''):gsub('[^%w%._%-]+', '-')
  return s
end

-- Where a sym's file is on disk. lsp.lua puts it on the sym (`abs`); a sym
-- without one (made by hand, saved before `abs` existed) hangs off the cwd.
local function abs_path(sym)
  if sym.abs then return sym.abs end
  if sym.path:sub(1, 1) == '/' then return sym.path end
  return vim.fn.getcwd() .. '/' .. sym.path
end

-- Export directory for a dive rooted at `sym` (the current root when omitted):
-- the override, else <git-common-dir>/spelunk of the repo holding the root's
-- file, else nvim's state dir when the root is not in a repo.
function M.export_dir(sym)
  if config.export_dir then return vim.fs.normalize(config.export_dir) end
  sym = sym or (session and session.g:root())
  local git_root = sym and pr.root(abs_path(sym))
  git_root = git_root or pr.current_root()
  if git_root then return pr.common_dir(git_root) .. '/spelunk' end
  return vim.fn.stdpath('state') .. '/spelunk'
end

function M.export_path()
  if not session then return nil end
  return session.dir .. '/' .. session.name .. '.md'
end

-- The live graph, nil without a session. Read-only by convention: mutate
-- through events or commands so the split and export stay in step.
function M.graph()
  return session and session.g
end

function M.name()
  return session and session.name
end

local function write_export()
  local path = M.export_path()
  local ok = pcall(function()
    vim.fn.mkdir(session.dir, 'p')
    local lines = vim.split(render().markdown(session.g, session.name), '\n', { plain = true })
    if lines[#lines] == '' then lines[#lines] = nil end
    if vim.fn.writefile(lines, path) ~= 0 then error('cannot write ' .. path) end
  end)
  if not ok then
    return false, 'export failed: ' .. path .. ' — set export_dir via setup()'
  end
  return true
end

-- Explicit export (:SpelunkExport): a failure always notifies.
function M.export()
  if not session then return false end
  local ok, msg = write_export()
  if not ok then notify(msg, vim.log.levels.WARN) end
  session.write_failed = not ok
  return ok
end

-- Automatic export on every graph change: one notify per failure streak, or
-- a read-only dir would notify on each navigation step.
local function auto_export()
  local ok, msg = write_export()
  if not ok and not session.write_failed then notify(msg, vim.log.levels.WARN) end
  session.write_failed = not ok
end

local function split_open()
  return split.win and vim.api.nvim_win_is_valid(split.win)
    and split.buf and vim.api.nvim_buf_is_valid(split.buf)
end

-- The split's cursor follows the current node, unless you are in the split
-- browsing it: then it stays on the same sym (the same line number when that
-- sym's line is gone). A fresh split always starts on the current node.
function M.render()
  if not (split_open() and session) then return end
  local lines, index, here = render().tree(session.g, { width = vim.api.nvim_win_get_width(split.win) })
  local row = vim.api.nvim_win_get_cursor(split.win)[1]
  local was = split.index and split.index[row]
  local browsing = split.index ~= nil and vim.api.nvim_get_current_win() == split.win
  vim.bo[split.buf].modifiable = true
  vim.api.nvim_buf_set_lines(split.buf, 0, -1, false, lines)
  vim.bo[split.buf].modifiable = false
  split.index = index
  local target = math.min(row, #lines)
  if not browsing then
    target = here or target
  elseif was then
    local k = graph().key(was)
    for i = 1, #lines do
      if index[i] and graph().key(index[i]) == k then target = i break end
    end
  end
  vim.api.nvim_win_set_cursor(split.win, { math.max(target, 1), 0 })
end

local function changed()
  M.render()
  auto_export()
end

function M.start(root, name)
  name = sanitize(name ~= '' and name or nil)
  if name == '' then name = sanitize(root.name .. '-' .. os.date('%H%M')) end
  session = {
    g = graph().new(root),
    name = name,
    dir = M.export_dir(root),
    write_failed = false,
  }
  split.index = nil
  changed()
end

function M.stop()
  M.close()
  session = nil
end

local function cursor_sym(cb)
  local c = vim.api.nvim_win_get_cursor(0)
  lsp.resolve(0, c[1], c[2], cb)
end

local function on_event(ev)
  if ev.type == 'expand' then
    if not session then M.start(ev.from) end
    session.g:expand(ev.from, ev.edge, ev.children)
    changed()
  elseif ev.type == 'visit' and session then
    if session.g:visit(ev.sym) ~= 'noop' then changed() end
  end
end

function M.note(text, sym)
  if not session then return notify('no session', vim.log.levels.WARN) end
  sym = sym or session.g:current()
  local function apply(t)
    if t == nil then return end
    session.g:note(sym, t)
    changed()
  end
  if text and text ~= '' then return apply(text) end
  local info = session.g:info(sym)
  vim.ui.input({ prompt = 'note (' .. sym.name .. '): ', default = info and info.note or '' }, apply)
end

-- Under-cursor node in the split, or nil for frontier/summary lines.
local function split_node()
  local sym = split.index and split.index[vim.api.nvim_win_get_cursor(0)[1]]
  if sym and session.g:info(sym) then return sym end
end

-- The window <CR> jumps in: the previous one, else any other window in the
-- tab, else a fresh one to the left.
local function jump_window()
  local prev = vim.fn.win_getid(vim.fn.winnr('#'))
  if prev ~= 0 and prev ~= split.win then return prev end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= split.win and vim.api.nvim_win_get_config(w).relative == '' then return w end
  end
  vim.cmd('aboveleft vnew')
  local w = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(split.win, M.WIDTH)
  return w
end

-- Visit detection in lsp.lua sees the landing (BufEnter/CursorMoved), so the
-- jump records itself; recording it here too would double-count.
local function jump()
  local sym = split.index and split.index[vim.api.nvim_win_get_cursor(0)[1]]
  if not sym then return end
  vim.api.nvim_set_current_win(jump_window())
  local path = abs_path(sym)
  if vim.fs.normalize(vim.api.nvim_buf_get_name(0)) ~= vim.fs.normalize(path) then
    local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
    if not ok then return notify(tostring(err), vim.log.levels.ERROR) end
  end
  local last = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.min(sym.line, last), math.max((sym.col or 1) - 1, 0) })
  vim.cmd('normal! zz')
end

local function map_split(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true, desc = 'spelunk: ' .. desc })
  end
  map('<CR>', jump, 'jump to node')
  map('n', function() M.note(nil, split_node()) end, 'note')
  map('p', function()
    local sym = split_node()
    if not sym then return notify('not a node', vim.log.levels.WARN) end
    session.g:prune(sym, not session.g:info(sym).pruned)
    changed()
  end, 'prune/unprune')
  map('r', M.render, 're-render')
  map('q', M.close, 'close')
end

function M.open()
  if not session then return notify('no session', vim.log.levels.WARN) end
  if split_open() then return end
  local origin = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'spelunk'
  vim.cmd('botright vertical ' .. M.WIDTH .. 'split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  local wo = vim.wo[win]
  wo.wrap, wo.cursorline, wo.winfixwidth = false, true, true
  wo.number, wo.relativenumber, wo.spell = false, false, false
  wo.signcolumn, wo.foldcolumn = 'no', '0'
  split.win, split.buf, split.index = win, buf, nil
  map_split(buf)
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function() split.win, split.buf, split.index = nil, nil, nil end,
  })
  M.render()
  -- The split is a sidebar: navigation carries on where it was.
  if vim.api.nvim_win_is_valid(origin) then vim.api.nvim_set_current_win(origin) end
end

-- Closes the split in whichever tab holds it. The last window of the last
-- tab cannot close, so it gets a fresh scratch buffer instead.
function M.close()
  if split.win and vim.api.nvim_win_is_valid(split.win) then
    local tab = vim.api.nvim_win_get_tabpage(split.win)
    local wins = vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == '' end,
      vim.api.nvim_tabpage_list_wins(tab))
    if #wins == 1 and #vim.api.nvim_list_tabpages() == 1 then
      vim.api.nvim_win_set_buf(split.win, vim.api.nvim_create_buf(false, true))
    else
      pcall(vim.api.nvim_win_close, split.win, true)
    end
  end
  split.win, split.buf, split.index = nil, nil, nil
end

function M.toggle()
  if split_open() then M.close() else M.open() end
end

local function commands()
  local cmd = vim.api.nvim_create_user_command
  cmd('SpelunkStart', function(o)
    local name = table.concat(o.fargs, ' ')
    cursor_sym(function(sym) M.start(sym, name) end)
  end, { nargs = '*', desc = 'spelunk: new session rooted at the cursor symbol' })
  cmd('SpelunkStop', M.stop, { desc = 'spelunk: end the session' })
  cmd('SpelunkOpen', M.toggle, { desc = 'spelunk: toggle the tree split' })
  cmd('SpelunkNote', function(o) M.note(o.args) end,
    { nargs = '*', desc = 'spelunk: note on the current node' })
  cmd('SpelunkMark', function()
    -- Without a session a visit has nowhere to go; marking starts one here.
    if session then lsp.mark() else cursor_sym(function(sym) M.start(sym) end) end
  end, { desc = 'spelunk: record the cursor symbol as a visit' })
  cmd('SpelunkExport', function()
    if not session then return notify('no session', vim.log.levels.WARN) end
    if M.export() then notify('wrote ' .. M.export_path()) end
  end, { desc = 'spelunk: write the export now' })
end

-- Re-callable: a later call replaces the options (probes point export_dir at
-- a temp dir) without dropping an open session.
function M.setup(opts)
  config = vim.tbl_extend('force', {}, opts or {})
  lsp.setup()
  lsp.on_event(on_event)
  lsp.set_known(function(sym) return session ~= nil and session.g:has(sym) end)
  commands()
end

return M
