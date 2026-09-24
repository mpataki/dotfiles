local P = require('probe')
local render = require('mpataki.review.render')

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'l1', 'l2', 'l3', 'l4', 'l5' })

-- Range tints and virtual lines share one namespace, so filter by what a mark
-- carries rather than counting every extmark in it.
local function virt_marks(b)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(b, render.ns, 0, -1, { details = true })) do
    if m[4].virt_lines then table.insert(out, m) end
  end
  return out
end

local function tint_marks(b, hl)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(b, render.ns, 0, -1, { details = true })) do
    if m[4].line_hl_group and (hl == nil or m[4].line_hl_group == hl) then table.insert(out, m) end
  end
  table.sort(out, function(x, y) return x[2] < y[2] end)
  return out
end

local function tint_rows(b, hl)
  local out = {}
  for _, m in ipairs(tint_marks(b, hl)) do table.insert(out, m[2]) end
  return out
end

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
local marks = virt_marks(buf)
P.eq(#marks, 2, 'one pending + one RIGHT remote rendered')

local by_row = {}
for _, m in ipairs(marks) do by_row[m[2]] = m[4] end
P.ok(by_row[1] ~= nil, 'pending at row 1 (line 2)')
P.eq(#by_row[1].virt_lines, 2, 'pending body renders two virt lines')
P.eq(table.concat(by_row[1].virt_lines[1][1][2], '+'), 'ReviewPendingRange+ReviewPending',
  'pending comment line wears the range tint under its own foreground')
P.ok(by_row[3] ~= nil, 'remote at row 3 (line 4)')
P.ok(by_row[3].virt_lines[1][1][1]:find('@bob', 1, true) ~= nil, 'remote prefixed with author')
P.eq(table.concat(by_row[3].virt_lines[1][1][2], '+'), 'ReviewRemoteRange+ReviewRemote',
  'remote comment line wears the range tint under its own foreground')

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
P.ok(vim.fn.hlexists('ReviewPendingRange') == 1, 'ReviewPendingRange defined')
P.ok(vim.fn.hlexists('ReviewRemoteRange') == 1, 'ReviewRemoteRange defined')

render.render(buf, 'a.go', entries, threads)
render.clear(buf)
P.eq(#vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, {}), 0, 'clear removes every mark')

-- GitHub hands back comment bodies with CRLF endings. Splitting on '\n' alone
-- leaves a trailing '\r', which nvim transliterates into a literal '^M' at the
-- end of every line but the last -- so read the text back off the extmark, not
-- off the input, to see it.
render.render(buf, 'a.go', { { path = 'a.go', line = 1, body = 'crlf one\r\ncrlf two' } }, {})
local crlf = virt_marks(buf)
P.eq(#crlf, 1, 'CRLF body renders one mark')
P.eq(#crlf[1][4].virt_lines, 2, 'CRLF body splits into two virt lines')
P.eq(crlf[1][4].virt_lines[1][1][1]:sub(-8), 'crlf one', 'CRLF first virt line ends at the body text')
P.ok(crlf[1][4].virt_lines[1][1][1]:find('^M', 1, true) == nil, 'CRLF first virt line has no ^M')
P.eq(crlf[1][4].virt_lines[2][1][1]:sub(-8), 'crlf two', 'CRLF second virt line ends at the body text')

-- The continuation indent is padded to the *display* width of the prefix, not
-- its byte length: an author name can carry multi-byte characters ('@zoe:' is
-- 7 bytes wide and 6 columns wide), so equal body lines must still line up.
render.render(buf, 'a.go', {}, {
  { id = 7, path = 'a.go', line = 1, side = 'RIGHT', body = 'ab\ncd', author = 'zoë' },
})
local aligned = virt_marks(buf)[1][4].virt_lines
P.eq(vim.fn.strdisplaywidth(aligned[2][1][1]), vim.fn.strdisplaywidth(aligned[1][1][1]),
  'continuation line aligns under the first line')

-- gh.pending_review yields line = nil when GitHub nils both `line` and
-- `original_line`; one such entry must not take the whole buffer down with it.
local ok_nil = pcall(render.render, buf, 'a.go', {
  { path = 'a.go', line = nil, body = 'no line' },
  { path = 'a.go', line = 2, body = 'has line' },
}, {})
P.ok(ok_nil, 'entry with no line does not error')
P.eq(#virt_marks(buf), 1,
  'line-less entry skipped, its sibling still rendered')

-- Deliberate: a comment anchored past the end of the buffer draws nothing.
-- Quickfix still lists it, and a clamped mark would lie about where it is.
render.render(buf, 'a.go', { { path = 'a.go', line = 99, body = 'past eof' } }, {})
P.eq(#vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, {}), 0,
  'line past the end of the buffer renders no mark')

-- gh.threads defaults a null body to ''; the mark still has to say a comment is
-- here rather than vanish.
render.render(buf, 'a.go', {}, { { id = 9, path = 'a.go', line = 1, side = 'RIGHT', body = '', author = 'dee' } })
local empty = virt_marks(buf)
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

-- A multi-line comment rendered only under its end line is invisible *as* a
-- range. A background tint on every covered line shows its extent without
-- taking the single sign-column slot away from mini.diff's git signs.
local wide = vim.api.nvim_create_buf(false, true)
local wide_lines = {}
for i = 1, 14 do wide_lines[i] = 'w' .. i end
vim.api.nvim_buf_set_lines(wide, 0, -1, false, wide_lines)

render.render(wide, 'a.go', { { path = 'a.go', line = 12, start_line = 10, body = 'range' } }, {})
P.eq(table.concat(tint_rows(wide, 'ReviewPendingRange'), ','), '9,10,11', 'range 10-12 tints every covered row')
P.eq(#tint_rows(wide), 3, '…and nothing outside it')
-- Low priority is the point: mini.diff paints changed lines with its own line
-- background through an overlay, and it has to win where the two meet.
for _, m in ipairs(tint_marks(wide, 'ReviewPendingRange')) do
  P.eq(m[4].priority, 50, 'tint at row ' .. m[2] .. ' stays under mini.diff')
end
local wide_virt = virt_marks(wide)
P.eq(#wide_virt, 1, 'the range still renders one virt_lines mark')
P.eq(wide_virt[1][2], 11, '…under its end line')
local wide_first = wide_virt[1][4].virt_lines[1][1][1]
P.eq(wide_first:sub(1, 10), '[pending] ', 'the comment line opens with the pending prefix: ' .. wide_first)
P.ok(wide_first:find('┃', 1, true) == nil, 'no gutter bar glyph left in the text column: ' .. wide_first)

render.render(wide, 'a.go', { { path = 'a.go', line = 4, body = 'single' } }, {})
P.eq(table.concat(tint_rows(wide, 'ReviewPendingRange'), ','), '3', 'a single-line entry tints exactly its own line')
P.eq(#tint_rows(wide), 1, '…and tints it once')

-- A remote range reads the same way, in its own tint.
render.render(wide, 'a.go', {}, {
  { id = 1, path = 'a.go', line = 8, start_line = 6, side = 'RIGHT', body = 'remote range', author = 'bob' },
  { id = 2, path = 'a.go', line = 2, start_line = 1, side = 'LEFT', body = 'left range', author = 'amy' },
})
P.eq(table.concat(tint_rows(wide, 'ReviewRemoteRange'), ','), '5,6,7', 'a remote range tints its covered rows')
P.eq(#tint_rows(wide, 'ReviewPendingRange'), 0, '…in ReviewRemoteRange, not ReviewPendingRange')
P.eq(#tint_rows(wide), 3, 'a LEFT-side thread tints nothing')

-- Tints live in the same namespace, so a re-render wipes them with everything else.
render.render(wide, 'a.go', {}, {})
P.eq(#vim.api.nvim_buf_get_extmarks(wide, render.ns, 0, -1, {}), 0, 're-render clears range tints')

-- A range whose tail runs past the end of the buffer tints only the lines that
-- exist, the same gate `mark` applies to the virtual lines.
render.render(wide, 'a.go', { { path = 'a.go', line = 16, start_line = 13, body = 'over the edge' } }, {})
P.eq(table.concat(tint_rows(wide, 'ReviewPendingRange'), ','), '12,13', 'a range past EOF tints only real lines')
render.clear(wide)

-- `default = true` on the links is load-bearing: ':colorscheme' runs
-- ':highlight clear', which wipes an explicit link but leaves a default one.
vim.cmd.colorscheme('habamax')
P.eq(vim.api.nvim_get_hl(0, { name = 'ReviewPending' }).link, 'DiagnosticVirtualTextWarn',
  'ReviewPending link survives a colorscheme reload')
P.eq(vim.api.nvim_get_hl(0, { name = 'ReviewRemote' }).link, 'Comment',
  'ReviewRemote link survives a colorscheme reload')
P.eq(vim.api.nvim_get_hl(0, { name = 'ReviewRemoteRange' }).link, 'CursorLine',
  'ReviewRemoteRange link survives a colorscheme reload')
P.ok(vim.api.nvim_get_hl(0, { name = 'ReviewPendingRange' }).bg ~= nil,
  'ReviewPendingRange keeps its tint across a colorscheme reload')

P.done()
