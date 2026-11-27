-- Tier 3: a <leader>gp rung view follows the rung branch's new heads while the
-- review worktree stays detached (rungs must stay movable by cascades).
-- Run: nvim --headless -c 'luafile probes/review/ladder_follow_probe.lua' -c 'qa'
local P = require('probe')
local follow = require('mpataki.ladder_follow')

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = vim.uv.fs_realpath(root)
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
-- Land a commit on `branch` the way a cascade does: in a throwaway worktree.
local function land(branch, file, msg)
  local op = root .. '-op'
  git(root, 'worktree', 'add', '-q', op, branch)
  commit(op, file, msg)
  git(root, 'worktree', 'remove', op)
end

git(root, 'init', '-q', '-b', 'main')
commit(root, 'base.txt', 'base')
git(root, 'switch', '-qc', 'rung1'); commit(root, 'one.txt', 'r1')
git(root, 'switch', '-qc', 'rung2'); commit(root, 'two.txt', 'r2')
git(root, 'switch', '-qc', 'fat'); commit(root, 'fat.txt', 'f1')
git(root, 'switch', '-q', '--detach', 'rung1')
git(root, 'worktree', 'add', '-q', root .. '-agent', 'fat')
local common = git(root, 'rev-parse', '--git-common-dir')
common = common:sub(1, 1) == '/' and common or (root .. '/' .. common)
vim.fn.writefile({ vim.json.encode({ schemaVersion = 1, stacks = { {
  trunk = { branch = 'main' }, branches = { { branch = 'rung1' }, { branch = 'rung2' } },
} } }) }, common .. '/gh-stack')
vim.fn.mkdir(common .. '/ladders', 'p')
vim.fn.writefile({ vim.json.encode({ fat_branch = 'fat', top = 'rung2' }) }, common .. '/ladders/fat.json')

vim.fn.chdir(root)
vim.cmd('edit ' .. root .. '/base.txt')
local pick_label = '^rung 2:'
vim.ui.select = function(items, opts, cb)
  for _, it in ipairs(items) do
    if opts.format_item(it):match(pick_label) then return cb(it) end
  end
  cb(nil)
end
local function keys(k)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), 'x', false)
end
local pr = require('mpataki.review.pr')
local function head() return git(root, 'rev-parse', 'HEAD') end

keys('<leader>gp')
P.wait(2000, function() return head() == git(root, 'rev-parse', 'rung2') end)
P.eq(follow.following(), 'rung2', 'picking rung 2 follows it')
P.eq(follow.check(), 'idle', 'no move, nothing to do')

land('rung2', 'two.txt', 'r2-fix')
P.eq(follow.check(), 'moved', 'rung 2 moved: view follows')
P.eq(head(), git(root, 'rev-parse', 'rung2'), 'HEAD at new rung 2 tip')
P.eq(vim.system({ 'git', '-C', root, 'symbolic-ref', '-q', 'HEAD' }):wait().code, 1, 'review worktree still detached')
P.eq(pr.info(root).base_sha, git(root, 'merge-base', 'HEAD', 'rung1'), 'base re-pinned to merge-base(rung2, rung1)')

-- A cascade from below: rung 1 gains a commit, rung 2 is rebased onto it.
land('rung1', 'one.txt', 'r1-late')
local op = root .. '-op'
git(root, 'worktree', 'add', '-q', op, 'rung2')
git(op, 'rebase', '-q', 'rung1')
git(root, 'worktree', 'remove', op)
P.eq(follow.check(), 'moved', 'cascade: view follows the rebased rung 2')
P.eq(pr.info(root).base_sha, git(root, 'rev-parse', 'rung1'), 'base = new rung 1 tip after cascade')

-- Dirty tree: never touched, waits.
vim.fn.writefile({ 'wip' }, root .. '/two.txt', 'a')
local before = head()
land('rung2', 'three.txt', 'r2-more')
P.eq(follow.check(), 'dirty', 'dirty tree: does not follow')
P.eq(head(), before, 'dirty tree: HEAD untouched')
git(root, 'checkout', '-q', '--', 'two.txt')
P.eq(follow.check(), 'moved', 'clean again: catches up')

-- Manual move away: stops following.
git(root, 'checkout', '-q', '--detach', 'rung1')
P.eq(follow.check(), 'stopped', 'manual checkout stops following')
P.eq(follow.following(), nil, 'not following')

-- <leader>gt stops following.
keys('<leader>gp')
P.wait(2000, function() return follow.following() == 'rung2' end)
keys('<leader>gt')
P.wait(300)
P.eq(follow.following(), nil, '<leader>gt stops following')

P.done()
