-- Tier 3: <leader>gp's fat entry in the two-worktree ladder model. When the
-- fat branch is attached in another (agent) worktree, picking it views the fat
-- tip detached instead of failing; with no other worktree it still attaches.
-- Run: nvim --headless -c 'luafile probes/review/ladder_worktree_probe.lua' -c 'qa'
local P = require('probe')

local function sh(dir, ...)
  local r = vim.system({ 'git', '-C', dir, '-c', 'commit.gpgsign=false', ... }, { text = true }):wait()
  assert(r.code == 0, table.concat({ ... }, ' ') .. ': ' .. (r.stderr or ''))
  return vim.trim(r.stdout)
end

local function fixture()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p')
  root = vim.uv.fs_realpath(root)
  local function commit(file, msg)
    vim.fn.writefile({ msg }, root .. '/' .. file, 'a')
    sh(root, 'add', file)
    sh(root, 'commit', '-qm', msg)
  end
  sh(root, 'init', '-q', '-b', 'main')
  commit('base.txt', 'base')
  sh(root, 'switch', '-qc', 'rung1'); commit('one.txt', 'r1')
  sh(root, 'switch', '-qc', 'fat'); commit('fat.txt', 'f1')
  sh(root, 'switch', '-q', '--detach', 'rung1')
  local common = sh(root, 'rev-parse', '--git-common-dir')
  common = common:sub(1, 1) == '/' and common or (root .. '/' .. common)
  vim.fn.writefile({ vim.json.encode({ schemaVersion = 1, stacks = { {
    trunk = { branch = 'main' }, branches = { { branch = 'rung1' } },
  } } }) }, common .. '/gh-stack')
  vim.fn.mkdir(common .. '/ladders', 'p')
  vim.fn.writefile({ vim.json.encode({ fat_branch = 'fat', top = 'rung1' }) }, common .. '/ladders/fat.json')
  return root
end

vim.ui.select = function(items, opts, cb)
  for _, it in ipairs(items) do
    if opts.format_item(it):match('^fat:') then return cb(it) end
  end
  cb(nil)
end
local function pick(root)
  vim.fn.chdir(root)
  vim.cmd('silent! %bwipeout!')
  vim.cmd('edit ' .. root .. '/one.txt')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<leader>gp', true, false, true), 'x', false)
  P.wait(2000, function() return sh(root, 'rev-parse', 'HEAD') == sh(root, 'rev-parse', 'fat') end)
end

-- Two worktrees: fat attached in the agent worktree.
local review = fixture()
local agent = review .. '-agent'
sh(review, 'worktree', 'add', '-q', agent, 'fat')
pick(review)
P.eq(sh(review, 'rev-parse', 'HEAD'), sh(review, 'rev-parse', 'fat'), 'two worktrees: review HEAD at fat tip')
P.eq(vim.system({ 'git', '-C', review, 'symbolic-ref', '-q', 'HEAD' }):wait().code, 1, 'two worktrees: review HEAD detached')
P.eq(sh(agent, 'symbolic-ref', '--short', 'HEAD'), 'fat', 'two worktrees: agent still attached to fat')

-- One worktree: fat re-attaches as before.
local solo = fixture()
pick(solo)
P.eq(sh(solo, 'symbolic-ref', '--short', 'HEAD'), 'fat', 'one worktree: fat attached')

P.done()
