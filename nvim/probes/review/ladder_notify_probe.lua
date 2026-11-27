-- Tier 3, end to end: a commit in the agent worktree reaches a following
-- <leader>gp view through git's reference-transaction hook (bin/ladder-notify,
-- global hook.ladder-follow in git/gitconfig) and the nvim socket — no
-- check() call from here. Also: repos without a ladder stay untouched.
-- Run: nvim --headless -c 'luafile probes/review/ladder_notify_probe.lua' -c 'qa'
local P = require('probe')
local follow = require('mpataki.ladder_follow')

local function git(dir, ...)
  local r = vim.system({ 'git', '-C', dir, '-c', 'commit.gpgsign=false', ... }, { text = true }):wait()
  assert(r.code == 0, table.concat({ ... }, ' ') .. ': ' .. (r.stderr or ''))
  return vim.trim(r.stdout)
end
local function commit(dir, file, msg)
  vim.fn.writefile({ msg }, dir .. '/' .. file, 'a')
  git(dir, 'add', file)
  git(dir, 'commit', '-qm', msg)
end

P.eq(git(vim.fn.getcwd(), 'config', '--get', 'hook.ladder-follow.event'), 'reference-transaction', 'global hook configured')

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = vim.uv.fs_realpath(root)
git(root, 'init', '-q', '-b', 'main')
commit(root, 'base.txt', 'base')
git(root, 'switch', '-qc', 'rung1'); commit(root, 'one.txt', 'r1')
git(root, 'switch', '-qc', 'fat'); commit(root, 'fat.txt', 'f1')
git(root, 'switch', '-q', '--detach', 'rung1')
local agent = root .. '-agent'
git(root, 'worktree', 'add', '-q', agent, 'fat')
local common = git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir')
vim.fn.writefile({ vim.json.encode({ schemaVersion = 1, stacks = { {
  trunk = { branch = 'main' }, branches = { { branch = 'rung1' } },
} } }) }, common .. '/gh-stack')
vim.fn.mkdir(common .. '/ladders', 'p')
vim.fn.writefile({ vim.json.encode({ fat_branch = 'fat', top = 'rung1' }) }, common .. '/ladders/fat.json')

-- Listen where ladder-notify will look (same rule as mpataki.nvim_goto).
local sock = '/tmp/nvim-sockets/' .. vim.fn.sha256(vim.fn.resolve(root)):sub(1, 16) .. '.pipe'
vim.fn.mkdir('/tmp/nvim-sockets', 'p')
P.ok(vim.fn.serverstart(sock) ~= '', 'listening on review worktree socket')

vim.fn.chdir(root)
vim.cmd('edit ' .. root .. '/base.txt')
vim.ui.select = function(items, opts, cb)
  for _, it in ipairs(items) do
    if opts.format_item(it):match('^fat:') then return cb(it) end
  end
  cb(nil)
end
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<leader>gp', true, false, true), 'x', false)
P.wait(2000, function() return follow.following() == 'fat' end)
P.eq(follow.following(), 'fat', 'following fat (attached in the agent worktree)')

-- The agent commits in its own worktree; nothing here calls check().
commit(agent, 'fat.txt', 'f2')
local tip = git(root, 'rev-parse', 'fat')
P.wait(5000, function() return git(root, 'rev-parse', 'HEAD') == tip end)
P.eq(git(root, 'rev-parse', 'HEAD'), tip, 'hook moved the review view to the new fat tip')

-- Repos without a ladder: the script exits before touching nvim or git.
local plain = vim.fn.tempname()
vim.fn.mkdir(plain, 'p')
git(plain, 'init', '-q', '-b', 'main')
local t0 = vim.uv.hrtime()
local r = vim.system({ vim.fn.expand('~/dotfiles/bin/ladder-notify'), 'committed' },
  { cwd = plain, stdin = '0 1 refs/heads/main\n' }):wait()
P.eq(r.code, 0, 'non-ladder repo: exits 0')
P.ok((vim.uv.hrtime() - t0) / 1e6 < 500, 'non-ladder repo: fast exit')

vim.fn.serverstop(sock)
P.done()
