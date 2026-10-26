package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')

-- <leader>gT / <leader>gF: neo-tree diffs against the same base as <leader>gS
-- and the mini.diff overlay, and marks the branch's committed changes (a stale
-- neo-tree override once dropped the base diff; an upstream status cache still
-- does on a repeat open — see TODO(neo-tree-status-cache)).
local fx = F.repo()
-- unchanged.txt lands on main and is merged in, so it exists at the merge-base
-- and in HEAD: the changed-files view must leave it out.
local function git(...)
  return vim.trim(vim.system({ 'git', '-C', fx.root, '-c', 'commit.gpgsign=false', ... }, { text = true }):wait().stdout)
end
git('checkout', '-q', 'main')
vim.fn.writefile({ 'same' }, fx.root .. '/unchanged.txt')
git('add', 'unchanged.txt')
git('commit', '-qm', 'unchanged')
git('checkout', '-q', 'feature')
git('merge', '-q', '--no-edit', 'main')
local base = git('merge-base', 'HEAD', 'main')

vim.fn.chdir(fx.root)
local ngit = require('neo-tree.git')
local file = fx.root .. '/sub/dir/file.txt'
local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

press('<leader>gT')
P.wait(5000, function()
  local _, wt = ngit.find_existing_worktree(file)
  return wt and wt.status_diff and wt.status_diff[base] ~= nil
end)

local code, from_base = ngit.find_existing_status_code(file, { [fx.root] = base })
P.ok(code ~= nil and from_base, 'committed branch change is marked from the base diff, got ' .. tostring(code))

vim.cmd('wincmd p | edit ' .. vim.fn.fnameescape(file))
P.wait(2000, function()
  local d = require('mini.diff').get_buf_data(0)
  return d and d.ref_text and d.ref_text:find('line 5\n', 1, true) ~= nil
end)
local d = require('mini.diff').get_buf_data(0)
P.ok(d and d.ref_text and d.ref_text:find('line 5\n', 1, true) ~= nil, 'overlay ref is the file at the same base')

local function listed(source)
  local s = require('neo-tree.sources.manager').get_state(source)
  if not s or not s.tree then return {} end
  local out = {}
  local function walk(node)
    if node.type == 'file' then out[node.path:sub(#fx.root + 2)] = true end
    for _, c in ipairs(node:get_child_ids()) do walk(s.tree:get_node(c)) end
  end
  for _, n in ipairs(s.tree:get_nodes()) do walk(n) end
  return out
end
-- Control: the full tree does show unchanged.txt, so its absence below means
-- the filter worked, not that the tree never loaded it.
P.ok(listed('filesystem')['unchanged.txt'], 'control: full tree lists unchanged.txt')

-- Twice: the second open hits neo-tree's unchanged-status cache.
for i = 1, 2 do
  vim.cmd('Neotree close')
  press('<leader>gF')
  P.wait(5000, function() return listed('git_status')['sub/dir/file.txt'] end)
  local got = listed('git_status')
  P.ok(got['sub/dir/file.txt'], ('open %d: changed-files tree lists the committed branch change'):format(i))
  P.eq(vim.tbl_count(got), 1, ('open %d: only branch changes listed: %s'):format(i, table.concat(vim.tbl_keys(got), ', ')))
  local st = require('neo-tree.sources.manager').get_state('git_status')
  P.eq((st.git_base_by_worktree or {})[fx.root], base, ('open %d: git_base is the branch merge-base'):format(i))
end

P.done()
