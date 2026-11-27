-- Tier 3, end to end: a <leader>gp rung view follows its branch. git moves the
-- worktree (bin/ladder-notify, the global reference-transaction hook, reading
-- <gitdir>/ladder-follow); nvim's HEAD watcher re-resolves the pinned base —
-- nothing here calls into the follow module after the pick.
-- Run: nvim --headless -c 'luafile probes/review/ladder_follow_probe.lua' -c 'qa'
local P = require('probe')
local follow = require('mpataki.ladder_follow')
local pr = require('mpataki.review.pr')

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
-- Move `branch` the way a cascade does: in a throwaway worktree.
local function on(branch, fn)
  local op = root .. '-op'
  git(root, 'worktree', 'add', '-q', op, branch)
  fn(op)
  git(root, 'worktree', 'remove', op)
end

P.eq(git(root, 'config', '--get', 'hook.ladder-follow.event'), 'reference-transaction', 'global hook configured')

git(root, 'init', '-q', '-b', 'main')
commit(root, 'base.txt', 'base')
git(root, 'switch', '-qc', 'rung1'); commit(root, 'one.txt', 'r1')
git(root, 'switch', '-qc', 'rung2'); commit(root, 'two.txt', 'r2')
git(root, 'switch', '-qc', 'fat'); commit(root, 'fat.txt', 'f1')
git(root, 'switch', '-q', '--detach', 'rung1')
git(root, 'worktree', 'add', '-q', root .. '-agent', 'fat')
local common = git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir')
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
local notes = {}
local notify = vim.notify
vim.notify = function(msg, ...) table.insert(notes, msg); return notify(msg, ...) end
local function keys(k)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), 'x', false)
end
local function head() return git(root, 'rev-parse', 'HEAD') end
local function overlay_base() return (notes[#notes] or ''):match('reviewing against (%x+)') end

keys('<leader>gp')
P.wait(2000, function() return head() == git(root, 'rev-parse', 'rung2') end)
P.ok(vim.deep_equal(follow.read(root), { branch = 'rung2', base = 'rung1' }), 'pick writes <gitdir>/ladder-follow: ' .. vim.inspect(follow.read(root)))

on('rung2', function(op) commit(op, 'two.txt', 'r2-fix') end)
local tip = git(root, 'rev-parse', 'rung2')
P.wait(3000, function() return head() == tip end)
P.eq(head(), tip, 'git moved the view to the new rung 2 tip')
P.eq(vim.system({ 'git', '-C', root, 'symbolic-ref', '-q', 'HEAD' }):wait().code, 1, 'review worktree still detached')

-- Cascade from below: the base moves too, and nvim notices via HEAD.
on('rung1', function(op) commit(op, 'one.txt', 'r1-late') end)
on('rung2', function(op) git(op, 'rebase', '-q', 'rung1') end)
tip = git(root, 'rev-parse', 'rung2')
local r1 = git(root, 'rev-parse', 'rung1')
P.wait(3000, function() return head() == tip end)
P.eq(head(), tip, 'cascade: view at rebased rung 2')
P.wait(2000, function() return overlay_base() == r1:sub(1, 8) end)
P.eq(pr.info(root).base_sha, r1, 'cascade: pinned base = new rung 1 tip')
P.eq(overlay_base(), r1:sub(1, 8), 'cascade: overlay re-based by the HEAD watcher')

-- Restart: the follow file restores the pin.
pr.pin_base(root, nil)
follow.restore(root)
P.eq(pr.info(root).base_sha, r1, 'restore after restart re-pins from the follow file')

-- <leader>gt: follow file gone, base unpinned, git no longer moves the view.
keys('<leader>gt')
P.wait(300)
P.eq(follow.read(root), nil, '<leader>gt stops following')
P.eq(pr.pinned(root), nil, '<leader>gt unpins')
local before = head()
on('rung2', function(op) commit(op, 'two.txt', 'r2-after') end)
vim.wait(800)
P.eq(head(), before, 'not following: git leaves the view alone')

vim.notify = notify
P.done()
