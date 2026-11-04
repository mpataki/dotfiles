-- Notes end to end: author one through the real float, flip it to a review
-- comment and back, peek a line in full. Fixture repo, seeded PR cache: no gh.
package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local render = require('mpataki.review.render')
local review = require('mpataki.review')
local notes = require('mpataki.review.notes')

vim.o.showmode = false

local function stub_texts(buf)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, { details = true })) do
    if m[4].virt_text then
      local parts = {}
      for _, c in ipairs(m[4].virt_text) do parts[#parts + 1] = c[1] end
      out[m[2] + 1] = table.concat(parts)
    end
  end
  return out
end

-- Pure: what the peek float says for a line.
local entries = {
  { path = 'a.go', line = 12, start_line = 10, kind = 'note', body = 'I think this retries\r\nthree times' },
  { path = 'a.go', line = 11, body = 'rename this' },
  { path = 'b.go', line = 11, body = 'other file' },
}
local threads = {
  { path = 'a.go', line = 11, side = 'RIGHT', author = 'bob', body = 'agree' },
  { path = 'a.go', line = 11, side = 'LEFT', author = 'amy', body = 'old side' },
}
local text = table.concat(notes.lines('a.go', 11, entries, threads), '\n')
P.ok(text:find('**pending** `a.go:11`', 1, true) ~= nil, 'peek shows the pending comment')
P.ok(text:find('**note** `a.go:10-12`', 1, true) ~= nil, 'peek shows a note whose range covers the line')
P.ok(text:find('I think this retries\nthree times', 1, true) ~= nil, 'peek shows the whole body, CR-free')
P.ok(text:find('@bob', 1, true) ~= nil, 'peek shows the remote thread')
P.ok(text:find('amy', 1, true) == nil and text:find('other file', 1, true) == nil, 'peek skips LEFT side and other files')
P.ok(text:find('pending', 1, true) < text:find('note', 1, true), 'pending before notes, like the stub')
P.eq(#notes.lines('a.go', 20, entries, threads), 0, 'nothing on an uncovered line')

-- Live: a fixture repo with a branch draft.
local fx = F.repo()
pr.clear_cache()
local info = pr.info(fx.root)
info.number = 7
info.head = fx.head_sha
vim.cmd('edit ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/file.txt'))
local code_buf = vim.api.nvim_get_current_buf()
local code_win = vim.api.nvim_get_current_win()
local ctx = assert(review.context(code_buf))

-- Author a note through the real float on a visual range.
vim.api.nvim_win_set_cursor(code_win, { 4, 0 })
review.comment({ range = 2, line1 = 2, line2 = 4 }, 'note')
local float_buf = vim.api.nvim_get_current_buf()
P.eq(vim.api.nvim_buf_get_name(float_buf), 'review://sub/dir/file.txt:2-4 [note]', 'note float is titled as a note')
vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, { 'reads config once' })
vim.cmd('write')
P.wait(100)
vim.api.nvim_set_current_win(code_win)
local doc = store.read(ctx.file)
P.eq(#doc.entries, 1, 'one entry saved')
P.eq(store.kind(doc.entries[1]), 'note', '…as a note')
P.eq(stub_texts(code_buf)[4], '[note] reads config once', 'the note stub renders on its end line')

-- A review comment on the same lines is a separate entry, not an edit of the note.
review.comment({ range = 2, line1 = 2, line2 = 4 })
float_buf = vim.api.nvim_get_current_buf()
P.eq(vim.api.nvim_get_current_line(), '', 'review float on the noted range opens empty, not on the note')
vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, { 'cache this' })
vim.cmd('write')
P.wait(100)
vim.api.nvim_set_current_win(code_win)
P.eq(#store.read(ctx.file).entries, 2, 'note and review comment coexist on one anchor')
P.eq(stub_texts(code_buf)[4], '[pending] cache this  [note] reads config once', 'both share the stub')

-- Normal-mode <leader>gn inside the range reopens the note, not the review.
vim.api.nvim_win_set_cursor(code_win, { 3, 0 })
review.comment(nil, 'note')
P.eq(vim.api.nvim_get_current_line(), 'reads config once', 'note gesture reopens the covering note')
vim.cmd('stopinsert')
vim.api.nvim_win_close(0, true)
vim.api.nvim_set_current_win(code_win)

-- Flip refuses when both kinds hold the anchor…
vim.api.nvim_win_set_cursor(code_win, { 3, 0 })
local before = table.concat(vim.fn.readfile(ctx.file), '\n')
notes.flip()
P.eq(table.concat(vim.fn.readfile(ctx.file), '\n'), before, 'flip with both kinds on the anchor changes nothing')

-- …and flips a lone entry, both ways.
local d = store.read(ctx.file)
store.remove(d, 'sub/dir/file.txt', 4, 2, 'review')
store.write(ctx.file, d)
notes.flip()
local flipped = store.read(ctx.file)
P.eq(store.kind(flipped.entries[1]), 'review', 'flip makes the note a review comment')
P.eq(flipped.entries[1].body, 'reads config once', '…with its body')
P.eq(stub_texts(code_buf)[4], '[pending] reads config once', '…and re-renders it as pending')
notes.flip()
P.eq(store.kind(store.read(ctx.file).entries[1]), 'note', 'flip again: back to a note')

-- Peek opens a float with the full body; it is not the current window.
vim.api.nvim_win_set_cursor(code_win, { 2, 0 })
local wins_before = #vim.api.nvim_list_wins()
notes.peek()
P.eq(#vim.api.nvim_list_wins(), wins_before + 1, 'peek opens a float')
P.eq(vim.api.nvim_get_current_win(), code_win, '…without taking focus')
local peek_win
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_config(w).relative ~= '' then peek_win = w end
end
local peek_text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(peek_win), 0, -1, false), '\n')
P.ok(peek_text:find('reads config once', 1, true) ~= nil, 'peek float carries the body: ' .. peek_text)

P.done()
