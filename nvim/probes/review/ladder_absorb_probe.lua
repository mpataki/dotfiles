-- Tier 3: <leader>cl hands review-worktree edits to the agent. Real float, real
-- tmux transport against a private server (-L <random>, -f /dev/null) and a
-- fake agent that records every byte it receives (same harness as
-- probes/ask/tmux_probe.lua). Never touches the live tmux.
-- Run: nvim --headless -c 'luafile probes/review/ladder_absorb_probe.lua' -c 'qa'
local P = require('probe')
local tmux = require('mpataki.ask.tmux')
local follow = require('mpataki.ladder_follow')

if vim.fn.executable('tmux') == 0 then
  print('SKIP no tmux')
  return P.done()
end

local sock = 'absorb-probe-' .. tostring(math.random(1e9))
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
dir = vim.uv.fs_realpath(dir)
local fake = dir .. '/2.1.999'
vim.fn.system({ 'cp', vim.fn.exepath('cat'), fake })
if vim.fn.has('mac') == 1 then vim.fn.system({ 'codesign', '-s', '-', '-f', fake }) end
local recv = dir .. '/recv.bin'
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
P.wait(3000, function() return (t({ 'display-message', '-p', '-t', agent_id, '#{pane_current_command}' })) == '2.1.999' end)

local function received()
  local f = io.open(recv, 'rb')
  if not f then return '' end
  local s = f:read('*a')
  f:close()
  return s
end
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
end

-- Review worktree following rung1, with a manual edit and a new file.
local root = dir .. '/repo'
local function git(...)
  local r = vim.system({ 'git', '-C', root, '-c', 'commit.gpgsign=false', ... }, { text = true }):wait()
  assert(r.code == 0, table.concat({ ... }, ' ') .. ': ' .. (r.stderr or ''))
  return vim.trim(r.stdout)
end
vim.fn.mkdir(root, 'p')
git('init', '-q', '-b', 'main')
vim.fn.writefile({ 'base' }, root .. '/one.txt')
git('add', 'one.txt'); git('commit', '-qm', 'base')
git('switch', '-qc', 'rung1'); git('switch', '-q', '--detach', 'rung1')
vim.fn.chdir(root)
vim.cmd.edit(vim.fn.fnameescape(root .. '/one.txt'))
follow.start(root, 'rung1', 'main')

P.ok(vim.fn.maparg('<leader>cl', 'n') ~= '', '<leader>cl mapped')

-- Clean tree: nothing to absorb, no float.
local wins = #vim.api.nvim_list_wins()
feed(' cl')
P.eq(#vim.api.nvim_list_wins(), wins, 'clean tree: no float opened')

vim.fn.writefile({ 'base', 'my fix' }, root .. '/one.txt')
vim.fn.writefile({ 'new' }, root .. '/new.txt')
vim.cmd('checktime')
feed(' cl')
local float = vim.api.nvim_get_current_win()
local title = vim.api.nvim_win_get_config(float).title
title = type(title) == 'table' and title[1][1] or tostring(title)
P.ok(title:find('absorb 2 edit(s) on rung1 → claude probe:0 ' .. agent_id, 1, true) ~= nil, 'float title: ' .. title)

feed('<Esc>ithe null check belongs in rung1, keep the test<Esc>:w<CR>')
P.wait(2000, function() return received():sub(-1) == '\r' end)
local msg = received()
P.ok(msg:find(root, 1, true) ~= nil, 'message names the review worktree')
P.ok(msg:find('viewing rung1 (rung below: main)', 1, true) ~= nil, 'message names the view and rung below')
P.ok(msg:find('Changed: one.txt, new.txt', 1, true) ~= nil, 'message lists changed files, untracked included')
P.ok(msg:find('the null check belongs in rung1, keep the test', 1, true) ~= nil, 'message carries the typed context')
P.ok(msg:find('"Review-worktree edits"', 1, true) ~= nil, 'message points at the skill section')

t({ 'kill-server' })
P.done()
