-- Tier 3: the real transport and <leader>cc, against a private tmux server
-- (-L <random>, -f /dev/null), never the live one. The fake agent is a copy of
-- cat named like a Claude version, in a raw-mode pane that asked for bracketed
-- paste, writing every byte it gets to a file.
local P = require('probe')
local tmux = require('mpataki.ask.tmux')
local ask = require('mpataki.ask')

if vim.fn.executable('tmux') == 0 then
  print('SKIP no tmux')
  return P.done()
end

local sock = 'ask-probe-' .. tostring(math.random(1e9))
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
dir = vim.uv.fs_realpath(dir)
local fake = dir .. '/2.1.999'
vim.fn.system({ 'cp', vim.fn.exepath('cat'), fake })
-- macOS SIGKILLs a copied system binary (its signature no longer matches the
-- path); an ad-hoc re-sign makes it runnable.
if vim.fn.has('mac') == 1 then vim.fn.system({ 'codesign', '-s', '-', '-f', fake }) end
local recv = dir .. '/recv.bin'

-- -f /dev/null: the user's tmux.conf (base-index 1, hooks) stays out of it.
local base = { 'tmux', '-L', sock, '-f', '/dev/null' }
local function t(args)
  local r = vim.system(vim.list_extend(vim.deepcopy(base), args), { text = true }):wait()
  return vim.trim(r.stdout or ''), r.code
end

local agent_cmd = ("printf '\\033[?2004h'; stty raw -echo; exec %s > %s")
  :format(vim.fn.shellescape(fake), vim.fn.shellescape(recv))
local agent_id = t({ 'new-session', '-d', '-P', '-F', '#{pane_id}', '-s', 'probe', '-x', '120', '-y', '30',
  '-c', dir, agent_cmd })
local me_id = t({ 'split-window', '-P', '-F', '#{pane_id}', '-t', agent_id, '-c', dir, 'sleep 600' })

tmux.argv = base
vim.env.TMUX = '/tmp/' .. sock .. ',0,0'
vim.env.TMUX_PANE = me_id

local function cmd_of(id) return (t({ 'display-message', '-p', '-t', id, '#{pane_current_command}' })) end
P.wait(3000, function() return cmd_of(agent_id) == '2.1.999' end)
P.eq(cmd_of(agent_id), '2.1.999', 'fixture: tmux reports the fake agent by its version-like name')

local me = tmux.me()
P.eq(me and me.id, me_id, 'me: own pane from $TMUX_PANE')

local resolved
ask.resolve(function(row) resolved = row end)
P.eq(resolved and resolved.id, agent_id, 'resolve: the Claude pane in my window')

local function received()
  local f = io.open(recv, 'rb')
  if not f then return '' end
  local s = f:read('*a')
  f:close()
  return s
end
local function since(n) return received():sub(n + 1) end
local function arrived(n)
  return function() return since(n):sub(-1) == '\r' end
end
local function float_gone()
  return function() return vim.api.nvim_win_get_config(0).relative == '' end
end
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
end

local ok, err = tmux.send(agent_id, 'line one\nline two')
P.ok(ok, 'send: ok ' .. tostring(err))
P.wait(2000, arrived(0))
P.eq(received(), '\27[200~line one\rline two\27[201~\r',
  'send: one bracketed paste with the newline inside, then exactly one Enter')

-- End to end: <leader>cc on line 2, type, :w. startinsert! has not landed when
-- keys are fed headless, so the probe enters insert mode itself.
local file = dir .. '/code.txt'
vim.fn.writefile({ 'a', 'b', 'c' }, file)
vim.cmd.edit(vim.fn.fnameescape(file))
P.ok(vim.fn.maparg('<leader>cc', 'n') ~= '' and vim.fn.maparg('<leader>cc', 'x') ~= '', '<leader>cc mapped n + x')

vim.api.nvim_win_set_cursor(0, { 2, 0 })
local before = #received()
feed(' cc')
local float = vim.api.nvim_get_current_win()
local title = vim.api.nvim_win_get_config(float).title
title = type(title) == 'table' and title[1][1] or tostring(title)
P.ok(title:find('/code.txt:2 → claude probe:0 ' .. agent_id, 1, true) ~= nil,
  'float: title names ref and target — ' .. title)
feed('<Esc>iwhat is b?<Esc>:w<CR>')
P.wait(2000, arrived(before))
-- Not in a git repo, so the path is absolute.
P.eq(since(before), '\27[200~' .. file .. ':2\r\rwhat is b?\27[201~\r', 'float: :w sends ref + body and submits')
-- The float closes on a scheduled callback; let it run before the next gesture.
P.wait(1000, float_gone())
P.ok(vim.api.nvim_win_get_config(0).relative == '', 'float: closes after send')

-- Visual range.
before = #received()
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed('Vj cc')
feed('<Esc>irange?<Esc>:w<CR>')
P.wait(2000, arrived(before))
P.ok(since(before):find(file .. ':1-2\r', 1, true) ~= nil, 'visual: ref is the selected range')
P.wait(1000, float_gone())

-- Empty body sends nothing.
before = #received()
feed(' cc')
feed('<Esc>:w<CR>')
P.wait(300)
P.eq(since(before), '', 'empty body: nothing sent')
P.wait(1000, float_gone())

-- Send failure keeps the float and the text: the pane dies while you type.
feed(' cc')
local fwin = vim.api.nvim_get_current_win()
feed('<Esc>ikeep me<Esc>')
t({ 'kill-pane', '-t', agent_id })
feed(':w<CR>')
P.wait(300)
P.ok(vim.api.nvim_win_is_valid(fwin), 'send failure: float stays open')
P.eq(vim.api.nvim_win_is_valid(fwin) and vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(fwin), 0, -1, false)[1],
  'keep me', 'send failure: text intact')
if vim.api.nvim_win_is_valid(fwin) then vim.api.nvim_win_close(fwin, true) end

-- No Claude pane at all: no float opens.
feed(' cc')
P.wait(100)
P.ok(vim.api.nvim_win_get_config(0).relative == '', 'no Claude pane: no float opens')

t({ 'kill-server' })
P.done()
