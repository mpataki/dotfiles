-- Tier 3: the <leader>gp picker is a menu — the real telescope picker opens in
-- normal mode, j/k move, <CR> picks; other vim.ui.select calls keep insert mode.
-- Run: nvim --headless -c 'luafile probes/review/ladder_menu_probe.lua' -c 'qa'
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
git('switch', '-qc', 'fat'); commit('fat.txt', 'f1')
local common = git('rev-parse', '--git-common-dir')
common = common:sub(1, 1) == '/' and common or (root .. '/' .. common)
vim.fn.writefile({ vim.json.encode({ schemaVersion = 1, stacks = { {
  trunk = { branch = 'main' }, branches = { { branch = 'rung1' } },
} } }) }, common .. '/gh-stack')
vim.fn.mkdir(common .. '/ladders', 'p')
vim.fn.writefile({ vim.json.encode({ fat_branch = 'fat', top = 'rung1' }) }, common .. '/ladders/fat.json')

vim.fn.chdir(root)
vim.cmd('edit ' .. root .. '/fat.txt')
local function keys(k)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), 'x', false)
end

keys('<leader>gp')
P.wait(2000, function() return P.picker() ~= nil end)
local p = P.picker()
P.ok(p ~= nil, 'ladder picker opened')
P.eq(p and p.initial_mode, 'normal', 'opens in normal mode (no fuzzy prompt)')
P.wait(300) -- telescope enters its initial mode on a scheduled tick
local first = p and require('telescope.actions.state').get_selected_entry()
keys('j')
P.wait(200)
local second = p and require('telescope.actions.state').get_selected_entry()
P.ok(first and second and first.index ~= second.index, 'j moves the selection')
-- Entries: fat, rung 1, HEAD. After one j: rung 1 (telescope sorts by index).
P.ok(second and second.value.text.label:match('^rung 1:') ~= nil, 'j lands on rung 1: ' .. tostring(second and second.value.text.label))
keys('<CR>')
P.wait(2000, function() return git('rev-parse', 'HEAD') == git('rev-parse', 'rung1') end)
P.eq(git('rev-parse', 'HEAD'), git('rev-parse', 'rung1'), '<CR> picks rung 1')

-- Plain vim.ui.select still opens with the fuzzy prompt.
vim.ui.select({ 'a', 'b' }, { prompt = 'plain' }, function() end)
P.wait(1000, function() return P.picker() ~= nil end)
P.eq(P.picker() and P.picker().initial_mode, 'insert', 'other selects keep insert mode')
P.eq(require('telescope.config').values.initial_mode, 'insert', 'global default restored')
P.done()
