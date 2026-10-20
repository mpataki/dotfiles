-- Tier 3: the <leader>s* keys, fed through the real mappings on a plain file.
-- No LSP attaches, so the cursor resolves to a file-level sym: enough to drive
-- start, toggle, note, export and stop.
local P = require('probe')
local spelunk = require('mpataki.spelunk')

local dir = vim.fn.tempname() .. '-spelunk'
spelunk.setup({ export_dir = dir })

local file = vim.fn.tempname() .. '.txt'
vim.fn.writefile({ 'one', 'two' }, file)
vim.cmd.edit(file)
local code_win = vim.api.nvim_get_current_win()

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
end
local function split_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'spelunk' then return w end
  end
end

local mapped = true
for _, k in ipairs({ 'ss', 'so', 'sx', 'sn', 'sm', 'se' }) do
  local m = vim.fn.maparg('<leader>' .. k, 'n', false, true)
  local ok = m.desc and m.desc:find('^spelunk: ') ~= nil
  mapped = mapped and ok
  P.ok(ok, '<leader>' .. k .. ' mapped: ' .. tostring(m.desc))
end
-- Unmapped, the fed keys fall through to builtins (s = substitute) and strand
-- the probe in insert mode: stop on the failures above instead of hanging.
if not mapped then return P.done() end
P.ok(vim.fn.maparg('<leader>s\\', 'n') ~= '', 'split map <leader>s\\ still there')

feed(' ss')
P.wait(1000, function() return spelunk.graph() ~= nil and split_win() ~= nil end)
local g1 = spelunk.graph()
P.ok(g1 ~= nil, '<leader>ss starts a session')
P.ok(split_win() ~= nil, '<leader>ss opens the split')
P.eq(vim.api.nvim_get_current_win(), code_win, '<leader>ss leaves focus in the code window')

feed(' so')
P.ok(split_win() == nil, '<leader>so closes the split')
P.ok(spelunk.graph() == g1, '<leader>so keeps the session')
feed(' so')
P.ok(split_win() ~= nil, '<leader>so reopens it')

feed(' snkeyed note<CR>')
P.eq(g1:info(g1:current()).note, 'keyed note', '<leader>sn notes the current node')

feed(' se')
P.ok(vim.fn.filereadable(spelunk.export_path()) == 1, '<leader>se writes the export')

feed(' ss')
P.wait(1000, function() return spelunk.graph() ~= g1 end)
P.ok(spelunk.graph() ~= nil and spelunk.graph() ~= g1, '<leader>ss again resets to a fresh session')
P.eq(spelunk.graph():info(spelunk.graph():current()).note, nil, 'reset: fresh session has no notes')

feed(' sx')
P.ok(spelunk.graph() == nil and split_win() == nil, '<leader>sx ends the session and closes the split')

P.done()
