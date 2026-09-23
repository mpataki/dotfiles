local P = require('probe')
local render = require('mpataki.review.render')

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'l1', 'l2', 'l3', 'l4', 'l5' })

local entries = {
  { path = 'a.go', line = 2, body = 'pending one\nsecond line' },
  { path = 'other.go', line = 2, body = 'not this file' },
}
local threads = {
  { id = 1, path = 'a.go', line = 4, side = 'RIGHT', body = 'remote', author = 'bob' },
  { id = 2, path = 'a.go', line = 3, side = 'LEFT', body = 'old side', author = 'amy' },
  { id = 3, path = 'a.go', line = nil, side = 'RIGHT', body = 'no line', author = 'cat' },
}

render.render(buf, 'a.go', entries, threads)
local marks = vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, { details = true })
P.eq(#marks, 2, 'one pending + one RIGHT remote rendered')

local by_row = {}
for _, m in ipairs(marks) do by_row[m[2]] = m[4] end
P.ok(by_row[1] ~= nil, 'pending at row 1 (line 2)')
P.eq(#by_row[1].virt_lines, 2, 'pending body renders two virt lines')
P.eq(by_row[1].virt_lines[1][1][2], 'ReviewPending', 'pending highlight')
P.ok(by_row[3] ~= nil, 'remote at row 3 (line 4)')
P.ok(by_row[3].virt_lines[1][1][1]:find('@bob', 1, true) ~= nil, 'remote prefixed with author')
P.eq(by_row[3].virt_lines[1][1][2], 'ReviewRemote', 'remote highlight')

render.render(buf, 'a.go', {}, {})
P.eq(#vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, {}), 0, 're-render clears old marks')

render.quickfix('/root', entries, threads)
local qf = vim.fn.getqflist()
P.eq(#qf, 5, 'all entries and threads listed')
P.eq(qf[1].text:sub(1, 9), '[pending]', 'pending marked')
P.eq(vim.fn.bufname(qf[1].bufnr), '/root/a.go', 'quickfix path is root-joined')
P.eq(qf[1].lnum, 2, 'pending lnum')
P.ok(qf[3].text:find('@bob', 1, true) ~= nil, 'remote text has author')
P.eq(qf[5].lnum, 1, 'thread with no line lands on line 1')
P.ok(vim.fn.hlexists('ReviewPending') == 1, 'ReviewPending defined')

render.render(buf, 'a.go', entries, threads)
render.clear(buf)
P.eq(#vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, {}), 0, 'clear removes every mark')

-- GitHub hands back comment bodies with CRLF endings. Splitting on '\n' alone
-- leaves a trailing '\r', which nvim transliterates into a literal '^M' at the
-- end of every line but the last -- so read the text back off the extmark, not
-- off the input, to see it.
render.render(buf, 'a.go', { { path = 'a.go', line = 1, body = 'crlf one\r\ncrlf two' } }, {})
local crlf = vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, { details = true })
P.eq(#crlf, 1, 'CRLF body renders one mark')
P.eq(#crlf[1][4].virt_lines, 2, 'CRLF body splits into two virt lines')
P.eq(crlf[1][4].virt_lines[1][1][1]:sub(-8), 'crlf one', 'CRLF first virt line ends at the body text')
P.ok(crlf[1][4].virt_lines[1][1][1]:find('^M', 1, true) == nil, 'CRLF first virt line has no ^M')
P.eq(crlf[1][4].virt_lines[2][1][1]:sub(-8), 'crlf two', 'CRLF second virt line ends at the body text')

-- The continuation indent is padded to the *display* width of the prefix, not
-- its byte length: the prefix carries a multi-byte box-drawing glyph, so equal
-- body lines must still line up on screen.
render.render(buf, 'a.go', { { path = 'a.go', line = 1, body = 'ab\ncd' } }, {})
local aligned = vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, { details = true })[1][4].virt_lines
P.eq(vim.fn.strdisplaywidth(aligned[2][1][1]), vim.fn.strdisplaywidth(aligned[1][1][1]),
  'continuation line aligns under the first line')

-- gh.pending_review yields line = nil when GitHub nils both `line` and
-- `original_line`; one such entry must not take the whole buffer down with it.
local ok_nil = pcall(render.render, buf, 'a.go', {
  { path = 'a.go', line = nil, body = 'no line' },
  { path = 'a.go', line = 2, body = 'has line' },
}, {})
P.ok(ok_nil, 'entry with no line does not error')
P.eq(#vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, {}), 1,
  'line-less entry skipped, its sibling still rendered')

-- Deliberate: a comment anchored past the end of the buffer draws nothing.
-- Quickfix still lists it, and a clamped mark would lie about where it is.
render.render(buf, 'a.go', { { path = 'a.go', line = 99, body = 'past eof' } }, {})
P.eq(#vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, {}), 0,
  'line past the end of the buffer renders no mark')

-- gh.threads defaults a null body to ''; the mark still has to say a comment is
-- here rather than vanish.
render.render(buf, 'a.go', {}, { { id = 9, path = 'a.go', line = 1, side = 'RIGHT', body = '', author = 'dee' } })
local empty = vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, { details = true })
P.eq(#empty, 1, 'empty body still marks the line')
P.eq(#empty[1][4].virt_lines, 1, 'empty body renders one virt line')
P.ok(empty[1][4].virt_lines[1][1][1]:find('@dee', 1, true) ~= nil, 'empty body keeps the author prefix')

-- A trailing slash on root must not double the separator: nvim treats
-- '/root//a.go' as a different buffer than '/root/a.go', so the quickfix jump
-- would open a second buffer for the same file, with none of the extmarks in it.
render.quickfix('/root/', { { path = 'a.go', line = 2, body = 'x' } }, {})
P.eq(vim.fn.bufname(vim.fn.getqflist()[1].bufnr), '/root/a.go', 'trailing-slash root does not double the separator')

render.quickfix('/root', { { path = 'a.go', line = nil, body = 'no line' } }, {})
P.eq(vim.fn.getqflist()[1].lnum, 1, 'pending entry with no line lands on line 1')

-- gh.threads leaves `path` nil for a comment GitHub reports without one; a
-- quickfix item with no filename cannot be jumped to, and building one throws.
render.quickfix('/root', {}, { { id = 4, path = nil, line = 2, body = 'pathless', author = 'eve' } })
P.eq(#vim.fn.getqflist(), 0, 'thread with no path is left out of the quickfix list')

-- `default = true` on the links is load-bearing: ':colorscheme' runs
-- ':highlight clear', which wipes an explicit link but leaves a default one.
vim.cmd.colorscheme('habamax')
P.eq(vim.api.nvim_get_hl(0, { name = 'ReviewPending' }).link, 'DiagnosticVirtualTextWarn',
  'ReviewPending link survives a colorscheme reload')
P.eq(vim.api.nvim_get_hl(0, { name = 'ReviewRemote' }).link, 'Comment',
  'ReviewRemote link survives a colorscheme reload')

P.done()
