-- The <leader>gS PR-files picker, driven for real from a *subdirectory* of the
-- repo. Every git call it makes must resolve against the repo root, and the
-- entries it produces must open the file that was actually changed — nvim's cwd
-- is routinely somewhere else in (or outside) the repo.
package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')

vim.o.showmode = false

local fx = F.repo()
vim.cmd('edit ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/file.txt'))
vim.fn.chdir(fx.root .. '/sub/dir')

-- The picker's keymap is set in telescope's config, which lazy runs on first
-- require. Driving the mapping is the whole point: it is the surface a user has.
require('telescope')
P.wait(200)
P.ok(vim.fn.maparg('<leader>gS', 'n') ~= '', '<leader>gS is mapped')

vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<leader>gS', true, false, true), 'x', false)
P.wait(5000, function() local _, n = P.picker(); return n and n > 0 end)

local picker, n = P.picker()
P.ok(picker ~= nil, 'PR files picker opened')
P.eq(n, 1, 'the one file changed against the PR base is listed')

local entry = picker and picker.manager:get_entry(1)
P.eq(entry and entry.path, fx.root .. '/sub/dir/file.txt',
  'entry path is absolute, so it opens the changed file and not a cwd-relative twin')
P.eq(entry and entry.ordinal, 'sub/dir/file.txt', 'the label stays repo-relative')

P.done()
