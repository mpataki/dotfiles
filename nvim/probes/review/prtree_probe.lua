package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')

-- <leader>gT: the tree diffs against the same base as <leader>gS and the
-- mini.diff overlay, and marks the branch's committed changes (not only the
-- uncommitted ones — a stale neo-tree override once dropped the base diff).
local fx = F.repo()
vim.fn.chdir(fx.root)
local ngit = require('neo-tree.git')
local file = fx.root .. '/sub/dir/file.txt'

vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<leader>gT', true, false, true), 'x', false)
P.wait(5000, function()
  local _, wt = ngit.find_existing_worktree(file)
  return wt and wt.status_diff and wt.status_diff[fx.base_sha] ~= nil
end)

local state = require('neo-tree.sources.manager').get_state('filesystem')
P.eq((state.git_base_by_worktree or {})[fx.root], fx.base_sha, 'tree git_base is the branch merge-base')

local code, from_base = ngit.find_existing_status_code(file, { [fx.root] = fx.base_sha })
P.ok(code ~= nil and from_base, 'committed branch change is marked from the base diff, got ' .. tostring(code))

vim.cmd('wincmd p | edit ' .. vim.fn.fnameescape(file))
P.wait(2000, function()
  local d = require('mini.diff').get_buf_data(0)
  return d and d.ref_text and d.ref_text:find('line 5\n', 1, true) ~= nil
end)
local d = require('mini.diff').get_buf_data(0)
P.ok(d and d.ref_text and d.ref_text:find('line 5\n', 1, true) ~= nil, 'overlay ref is the file at the same base')

P.done()
