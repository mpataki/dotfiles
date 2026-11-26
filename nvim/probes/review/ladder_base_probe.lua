-- Tier 3: after <leader>gp picks a rung, every PR-base view resolves the same
-- base — merge-base(rung, rung below) — and <leader>gt unpins it.
-- Self-contained: builds a throwaway ladder repo whose rung 1 gained a commit
-- after rung 2 was built (un-cascaded), so the rung-1 tip is the wrong base.
-- Run: nvim --headless -c 'luafile probes/review/ladder_base_probe.lua' -c 'qa'
local P = require('probe')

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = vim.uv.fs_realpath(root)
local function git(...)
  local r = vim.system({ 'git', '-C', root, '-c', 'commit.gpgsign=false', ... }, { text = true }):wait()
  assert(r.code == 0, table.concat({ ... }, ' ') .. ': ' .. (r.stderr or ''))
  return vim.trim(r.stdout)
end
local function commit(file, msg)
  vim.fn.writefile({ msg }, root .. '/' .. file, 'a')
  git('add', file)
  git('commit', '-qm', msg)
end
git('init', '-q', '-b', 'main')
commit('base.txt', 'base')
git('switch', '-qc', 'rung1'); commit('one.txt', 'r1')
git('switch', '-qc', 'rung2'); commit('two.txt', 'r2')
git('switch', '-qc', 'fat'); commit('fat.txt', 'f1')
git('switch', '-q', 'rung1'); commit('one.txt', 'r1-late') -- not cascaded
git('switch', '-q', 'fat')

local common = git('rev-parse', '--git-common-dir')
common = common:sub(1, 1) == '/' and common or (root .. '/' .. common)
vim.fn.writefile({ vim.json.encode({ schemaVersion = 1, stacks = { {
  trunk = { branch = 'main' },
  branches = { { branch = 'rung1' }, { branch = 'rung2' } },
} } }) }, common .. '/gh-stack')
vim.fn.mkdir(common .. '/ladders', 'p')
vim.fn.writefile({ vim.json.encode({ fat_branch = 'fat', top = 'rung2' }) }, common .. '/ladders/fat.json')

vim.fn.chdir(root)
vim.cmd('edit ' .. root .. '/fat.txt')

local want = git('merge-base', 'rung2', 'rung1')
local tip = git('rev-parse', 'rung1')
P.ok(want ~= tip, 'fixture: rung 1 tip moved past rung 2 base')

local notes = {}
local notify = vim.notify
vim.notify = function(msg, ...) table.insert(notes, msg); return notify(msg, ...) end
vim.ui.select = function(items, opts, cb)
  for _, it in ipairs(items) do
    if opts.format_item(it):match('^rung 2:') then return cb(it) end
  end
  cb(nil)
end
local function keys(k)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), 'x', false)
end

keys('<leader>gp')
P.wait(3000, function() return git('rev-parse', 'HEAD') == git('rev-parse', 'rung2') end)
P.eq(git('rev-parse', 'HEAD'), git('rev-parse', 'rung2'), 'picker detached at rung 2')

local pr = require('mpataki.review.pr')
vim.cmd('DiffPRBase') -- what gS/gT/gF/gD run first
local info = pr.info(root, { refresh = true })
P.eq(info and info.base_sha, want, 'pr.info base = merge-base(rung2, rung1) after arg-less DiffPRBase')
P.ok(notes[#notes]:find(want:sub(1, 8), 1, true) ~= nil, 'overlay base = pinned base: ' .. notes[#notes])

keys('<leader>gS')
P.wait(3000, function() return P.picker() ~= nil end)
local p = P.picker()
P.ok(p and p.prompt_title:find(want:sub(1, 8), 1, true) ~= nil, 'gS diffs vs pinned base: ' .. (p and p.prompt_title or 'no picker'))
if p then require('telescope.actions').close(p.prompt_bufnr) end
P.wait(200)

keys('<leader>gt')
P.wait(500)
info = pr.info(root, { refresh = true })
P.eq(info and info.base_sha, git('merge-base', 'HEAD', 'main'), '<leader>gt unpins')

vim.notify = notify
P.done()
