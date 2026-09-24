-- Tier 3: the whole loop against gopls in ~/code/k9s — real call-hierarchy
-- requests and jumps, through lsp events, into the graph, the split buffer and
-- the export file. Asserts on the rendered split lines, not on graph internals.
local P = require('probe')
local K9S = vim.fn.expand('~/code/k9s')
if vim.fn.isdirectory(K9S) == 0 then
  print('SKIP corpus missing: ' .. K9S)
  return P.done()
end
vim.cmd.cd(K9S)
local spelunk = require('mpataki.spelunk')
local lsp = require('mpataki.spelunk.lsp')

local POD = 'internal/view/pod.go'
local FWD = 'internal/watch/forwarders.go'
local SETTLE = lsp.DEBOUNCE_MS * 4 + 400

-- Default export dir, before the override: the repo's common dir.
local common = vim.trim(vim.fn.system({ 'git', '-C', K9S, 'rev-parse', '--git-common-dir' }))
if common:sub(1, 1) ~= '/' then common = K9S .. '/' .. common end
common = vim.fn.fnamemodify(common, ':p'):gsub('/$', '')
P.eq(spelunk.export_dir({ name = 'x', kind = 12, path = POD, line = 1 }), common .. '/spelunk',
  'export dir: default is <git-common-dir>/spelunk')

local dir = vim.fn.tempname() .. '-spelunk'
spelunk.setup({ export_dir = dir })
P.eq(spelunk.export_dir(), dir, 'export dir: setup({ export_dir }) overrides')

local function split_buf()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == 'spelunk' then return b, w end
  end
end
local function lines()
  local b = split_buf()
  return b and vim.api.nvim_buf_get_lines(b, 0, -1, false) or {}
end
local function find(pat)
  for i, l in ipairs(lines()) do
    if l:find(pat) then return i, l end
  end
end
local function move(line, col)
  vim.api.nvim_win_set_cursor(0, { line, col })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
end
local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local s = f:read('*a')
  f:close()
  return s
end

vim.cmd('edit ' .. POD)
local buf = vim.api.nvim_get_current_buf()
local c
P.wait(20000, function()
  c = vim.lsp.get_clients({ bufnr = buf, name = 'gopls' })[1]
  return c ~= nil
end)
if not P.ok(c ~= nil, 'gopls attached to pod.go') then return P.done() end
local at66 = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 65, character = 17 } }
local ready = false
for _ = 1, 30 do
  local r = c:request_sync('textDocument/prepareCallHierarchy', at66, 5000, buf)
  if r and r.result and #r.result > 0 then ready = true break end
  P.wait(2000)
end
if not P.ok(ready, 'gopls workspace ready') then return P.done() end

-- start + split ---------------------------------------------------------------
move(66, 15)
P.wait(SETTLE)
vim.cmd('SpelunkStart dive one')
P.wait(5000, function() return spelunk.graph() ~= nil end)
P.eq(spelunk.name(), 'dive-one', 'start: name sanitized for filenames')
local first_export = spelunk.export_path()
P.eq(first_export, dir .. '/dive-one.md', 'start: export path is <export_dir>/<session>.md')

local origin = vim.api.nvim_get_current_win()
vim.cmd('SpelunkOpen')
local sb, sw = split_buf()
if not P.ok(sb ~= nil, 'open: split with filetype spelunk') then return P.done() end
P.eq(vim.api.nvim_get_current_win(), origin, 'open: focus stays in the code window')
P.eq(vim.api.nvim_win_get_width(sw), 40, 'open: 40 cols')
P.eq(vim.fn.win_screenpos(sw)[2] + 40, vim.o.columns + 1, 'open: rightmost')
P.eq(vim.bo[sb].buftype, 'nofile', 'open: scratch buffer')
P.eq(vim.bo[sb].modifiable, false, 'open: nomodifiable')
P.eq(vim.wo[sw].wrap, false, 'open: nowrap')
P.eq(vim.wo[sw].cursorline, true, 'open: cursorline')
P.ok((lines()[1] or ''):find('^▶ portForwardIndicator'), 'open: root rendered as current (decision 1: ▶ gutter)')

-- AC scenario: outgoing, jump to a callee, incoming there ---------------------
vim.lsp.buf.outgoing_calls()
P.wait(15000, function() return #lines() >= 7 end)
vim.cmd('cclose')
P.eq(#lines(), 7, 'outgoing: current root lists its six callees individually')
P.ok(find('%?→ IsPodForwarded'), 'outgoing: IsPodForwarded pending under the current node')

vim.cmd('edit ' .. FWD)
-- On the method name: call hierarchy on the receiver asks about Forwarders.
move(57, 22)
P.wait(10000, function() return find('^▶ .*IsPodForwarded') ~= nil end)
P.wait(SETTLE)
local i, l = find('IsPodForwarded')
P.ok(l and l:find('→ IsPodForwarded') and l:find('forwarders%.go:57') and l:find('^▶ '),
  'jump: explored callee drawn with → and marked current — ' .. tostring(l))

vim.lsp.buf.incoming_calls()
P.wait(15000, function() return find('%?← ') ~= nil end)
P.wait(SETTLE)
vim.cmd('cclose')
local got = lines()
P.ok(got[1]:find('^  portForwardIndicator%s+view/pod%.go:66'),
  'scenario: line 1 is the root, no longer current — ' .. got[1])
P.ok(find('^▶ .*IsPodForwarded') == i, 'scenario: explored callee still current')
P.ok(find('^  └─%? 5 unexplored callees$'), 'scenario: root shows frontier count for the 5 remaining callees')
P.ok(not find('↩ portForwardIndicator'),
  'decision 3: incoming calls naming the tree parent are the same fact as its callee, not echoed')
P.ok(#vim.tbl_filter(function(s) return s:find('%?← ') end, got) >= 1,
  'scenario: other callers pending individually under the current node')
local md = read(first_export) or ''
P.ok(md:find('```mermaid\ngraph TD', 1, true), 'export: file exists with a mermaid block')
P.ok(md:find('# spelunk: dive-one', 1, true) and md:find('portForwardIndicator', 1, true),
  'export: session title and root name present')

-- cursor stability, note, prune, <CR> ------------------------------------------
vim.api.nvim_win_set_cursor(sw, { 1, 0 })
vim.cmd('SpelunkNote the real check')
P.eq(lines()[i + 1], '  │   · the real check', ':SpelunkNote text: note on its own line under the current node')
P.eq(vim.api.nvim_win_get_cursor(sw)[1], i,
  'decision 1: re-render snaps the split cursor to the current node when focus is elsewhere')
local input = vim.ui.input
vim.ui.input = function(_, cb) cb('prompted') end
vim.cmd('SpelunkNote')
P.eq(lines()[i + 1], '  │   · prompted', ':SpelunkNote no args: prompts')
vim.api.nvim_set_current_win(sw)
vim.api.nvim_win_set_cursor(sw, { 1, 0 })
vim.ui.input = function(_, cb) cb('root note') end
vim.cmd('normal n')
vim.ui.input = input
P.eq(lines()[2], '  · root note', 'split n: prompts a note for the node under the cursor')
P.eq(vim.api.nvim_win_get_cursor(sw)[1], 1, 'decision 1: cursor in the split stays where the user put it')
P.ok((read(first_export) or ''):find('root note', 1, true), 'export: rewritten on change')

vim.api.nvim_win_set_cursor(sw, { 1, 0 })
vim.cmd('normal \r')
P.eq(vim.api.nvim_get_current_win(), origin, '<CR>: jumps in the previous window')
P.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':.'), POD, '<CR>: opened the node file')
P.eq(vim.api.nvim_win_get_cursor(0)[1], 66, '<CR>: at the node line')
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
P.wait(SETTLE * 2, function() return (lines()[1] or ''):find('^▶ ') ~= nil end)
P.ok((lines()[1] or ''):find('^▶ '), '<CR>: lsp visit detection moved current to the root')
local jumps = vim.tbl_filter(function(s) return s:find('%(jump%)') end, lines())
P.eq(#jumps, 0, '<CR>: retreat to an ancestor adds no edge')

-- Prune a node off the current path (pruning an ancestor of current renders
-- nothing: you are standing inside it).
vim.api.nvim_set_current_win(sw)
local pi = find('→ IsPodForwarded')
vim.api.nvim_win_set_cursor(sw, { pi, 0 })
vim.cmd('normal p')
P.ok((lines()[pi + 2] or ''):find('└─… %(pruned%)$'), 'split p: prunes the subtree under the cursor node')
vim.cmd('normal p')
P.ok(find('→ IsPodForwarded') == pi and not find('%(pruned%)'), 'split p again: unprunes')
vim.api.nvim_set_current_win(origin)

-- :SpelunkMark: a same-buffer move into an unknown sym is recorded only on ask.
move(45, 5)
P.wait(SETTLE)
local before = #lines()
vim.cmd('SpelunkMark')
P.wait(5000, function() return #lines() > before end)
P.ok(find('^▶ .*→ '), ':SpelunkMark: cursor sym becomes the current node')

-- q, export failure, replace, stop, auto-start ----------------------------------
vim.api.nvim_set_current_win(sw)
vim.cmd('normal q')
P.eq(split_buf(), nil, 'split q: closes')
vim.cmd('SpelunkOpen')
P.ok(split_buf() ~= nil, ':SpelunkOpen: reopens')
vim.cmd('SpelunkOpen')
P.eq(split_buf(), nil, ':SpelunkOpen: toggles closed')

local blocker = vim.fn.tempname()
vim.fn.writefile({ 'x' }, blocker)
spelunk.setup({ export_dir = blocker .. '/sub' })
local notes, notify = {}, vim.notify
vim.notify = function(msg, ...) notes[#notes + 1] = msg; return notify(msg, ...) end
move(66, 15)
vim.cmd('SpelunkStart broken')
P.wait(5000, function() return spelunk.name() == 'broken' end)
vim.cmd('SpelunkNote one')
vim.cmd('SpelunkNote two')
vim.notify = notify
local failures = vim.tbl_filter(function(m) return m:find('export failed') end, notes)
P.eq(#failures, 1, 'export: failed write notifies once, not per change')
P.ok((read(first_export) or ''):find('dive-one', 1, true), 'replace: previous export stays on disk')

spelunk.setup({ export_dir = dir })
vim.cmd('SpelunkStop')
P.eq(spelunk.graph(), nil, ':SpelunkStop: session gone')
move(66, 15)
vim.lsp.buf.outgoing_calls()
P.wait(15000, function() return spelunk.graph() ~= nil end)
P.wait(SETTLE)
vim.cmd('cclose')
local g = spelunk.graph()
P.eq(g and g:root().name, 'portForwardIndicator', 'auto-start: first expand roots a session at from')
P.eq(g and #g:frontier(), 6, 'auto-start: the expand that started it is recorded')
P.ok(spelunk.name() and spelunk.name():find('^portForwardIndicator%-%d%d%d%d$'),
  'auto-start: name defaults to <root>-<HHMM> — ' .. tostring(spelunk.name()))
P.ok(vim.uv.fs_stat(spelunk.export_path()) ~= nil, 'auto-start: export written')

P.done()
