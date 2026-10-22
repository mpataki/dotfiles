-- Regression: the split's window options (nonumber, signcolumn=no, nowrap,
-- winfixwidth) are the spelunk buffer's, not the window's. A file opened into
-- that window later, or a window split off it, gets the config's values back.
local P = require('probe')
local spelunk = require('mpataki.spelunk')
spelunk.setup({ export_dir = vim.fn.tempname() .. '-spelunk' })

local file = vim.fn.tempname() .. '.txt'
vim.fn.writefile({ 'one', 'two' }, file)
vim.cmd.edit(vim.fn.fnameescape(file))
local want = { number = vim.wo.number, signcolumn = vim.wo.signcolumn, wrap = vim.wo.wrap,
  winfixwidth = vim.wo.winfixwidth, cursorline = vim.wo.cursorline }

spelunk.start({ name = 'Root', kind = 12, path = 'a.go', line = 1 }, 'split')
spelunk.open()
local split
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'spelunk' then split = w end
end
P.ok(split ~= nil, 'split open')
P.ok(not vim.wo[split].number and vim.wo[split].signcolumn == 'no' and vim.wo[split].winfixwidth,
  'split: spelunk buffer shows with its own options')

local function same(w, label)
  for k, v in pairs(want) do
    P.eq(vim.wo[w][k], v, label .. ': ' .. k .. ' back to the config value')
  end
end

-- A window split off the sidebar starts from the config, not the sidebar.
vim.api.nvim_set_current_win(split)
vim.cmd('aboveleft vnew')
same(vim.api.nvim_get_current_win(), 'vnew from split')
vim.cmd.close()

-- The bug as seen: a file opened into the split window kept the bare gutter.
-- A fresh file: one shown before restores that window's options and hides it.
local fresh = vim.fn.tempname() .. '.txt'
vim.fn.writefile({ 'three' }, fresh)
vim.api.nvim_set_current_win(split)
vim.cmd.edit(vim.fn.fnameescape(fresh))
same(split, 'file opened into the split window')

P.done()
