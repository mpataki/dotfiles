package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')

local fx = F.repo()
-- The bug: cwd is a subdirectory, so ':.' paths are wrong for `git show`.
vim.fn.chdir(fx.root .. '/sub/dir')
vim.cmd('edit ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/file.txt'))
P.wait(500)

vim.cmd('DiffPRBase')
-- Wait for the ref text AND the recomputed hunks: mini.diff debounces its diff
-- update, so hunks still read 0 the instant set_ref_text lands.
P.wait(1500, function()
  local d = require('mini.diff').get_buf_data(0)
  return d and d.ref_text and d.ref_text:find('line 5\n', 1, true) ~= nil and #d.hunks >= 1
end)

local data = require('mini.diff').get_buf_data(0)
P.ok(data ~= nil, 'mini.diff attached')
P.ok(data and data.ref_text and data.ref_text:find('line 5\n', 1, true) ~= nil,
  'ref text is the base file, not empty (cwd-independent path)')
P.ok(data and #data.hunks >= 1 and #data.hunks <= 2, 'hunks reflect base..HEAD, got ' .. tostring(data and #data.hunks))

-- DiffReset drops the cached PR identity, so the next gesture re-resolves the
-- base instead of freezing on the one this session first computed.
vim.cmd('DiffReset')
P.wait(200)
local info = require('mpataki.review.pr').info(fx.root)
P.eq(info and info.base_sha, fx.base_sha, 'pr.info recomputes after DiffReset clears the cache')

P.done()
