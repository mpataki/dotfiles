-- Tier 2: payload and target are pure; call them directly.
local P = require('probe')
local payload = require('mpataki.ask.payload')
local target = require('mpataki.ask.target')

P.eq(payload.ref('a/b.lua', 12), 'a/b.lua:12', 'ref: single line')
P.eq(payload.ref('a/b.lua', 12, 12), 'a/b.lua:12', 'ref: one-line range collapses')
P.eq(payload.ref('a/b.lua', 12, 18), 'a/b.lua:12-18', 'ref: range')
P.eq(payload.body('  hi\r\nthere \n'), 'hi\nthere', 'body: trimmed, CR stripped')
P.eq(payload.body(' \n '), '', 'body: whitespace only is empty')
P.eq(payload.message('a.lua:3', 'why?'), 'a.lua:3\n\nwhy?', 'message: ref, blank line, body')

local root = vim.uv.fs_realpath(vim.fn.tempname() .. '') or vim.fn.tempname()
vim.fn.mkdir(root .. '/sub', 'p')
root = vim.uv.fs_realpath(root)
local file = root .. '/sub/x.lua'
vim.fn.writefile({ 'x' }, file)
P.eq(payload.path_for(file, root, root), 'sub/x.lua', 'path_for: pane at repo root → relative')
P.eq(payload.path_for(file, root, root .. '/sub'), file, 'path_for: pane elsewhere → absolute')
P.eq(payload.path_for(file, nil, root), file, 'path_for: no repo → absolute')

local out = table.concat({
  '%1\tdotfiles\t1\t2.1.309\t/Users/m/dotfiles',
  '%2\tdotfiles\t1\tnvim\t/Users/m/dotfiles',
  '%3\tdotfiles\t2\tzsh\t/Users/m/dotfiles',
  '%4\tb5\t1\t2.1.306\t/Users/m/go/src/b5',
  '%5\tb5\t2\t2.1.308\t/Users/m/code/b5',
  '%6\tb5\t3\tclaude\t/Users/m/code/b5',
  '%7\tweird name\t1\tzsh\t/tmp/with\ttab',
}, '\n')
local rows = target.parse(out)
P.eq(#rows, 7, 'parse: every row')
P.eq(rows[7].session, 'weird name', 'parse: session names with spaces')
P.ok(target.is_claude(rows[1]) and target.is_claude(rows[6]), 'is_claude: version string or `claude`')
P.ok(not target.is_claude(rows[2]) and not target.is_claude(rows[3]), 'is_claude: nvim/zsh are not')

local me = { id = '%2', session = 'dotfiles', window = '1' }
P.eq(target.choose(rows, me).pane.id, '%1', 'choose: the Claude pane in my window')
local other = { id = '%3', session = 'dotfiles', window = '2' }
P.eq(target.choose(rows, other).pane.id, '%1', 'choose: none in my window → the one in my session')
local b5 = { id = '%9', session = 'b5', window = '9' }
local c = target.choose(rows, b5)
P.ok(c.pick and #c.pick == 3, 'choose: several in session → pick')
P.eq(target.choose(rows, b5, '%5').pane.id, '%5', 'choose: remembered pane wins')
P.eq(target.choose(rows, me, '%5').pane.id, '%5', 'choose: remembered wins even across sessions')
P.eq(target.choose(rows, me, '%2').pane.id, '%1', 'choose: remembered pane no longer Claude → tiers')
P.eq(target.choose(rows, me, '%99').pane.id, '%1', 'choose: remembered pane gone → tiers')
local none = target.choose(rows, { id = '%7', session = 'weird name', window = '1' })
P.ok(none.err and none.err:find('weird name', 1, true) ~= nil, 'choose: no Claude pane → err naming the session')

P.done()
