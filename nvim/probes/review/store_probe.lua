local P = require('probe')
local store = require('mpataki.review.store')

local common = vim.fn.tempname()
local file = store.path(common, 42)
P.eq(file, common .. '/reviews/42.md', 'store path')
P.eq(store.remote_path(common, 42), common .. '/reviews/42.remote.json', 'remote path')

local doc = store.read(file)
P.eq(#doc.entries, 0, 'missing file reads as empty doc')

store.upsert(doc, { path = 'a/b.go', line = 42, body = 'first\n\nsecond para' })
store.upsert(doc, { path = 'a/b.go', line = 15, start_line = 10, body = 'range' })
doc.header = { repo = 'o/r#42', head = 'abc123', pushed = 'deadbeef' }
store.write(file, doc)

local text = table.concat(vim.fn.readfile(file), '\n')
P.ok(text:find('<!%-%- review: o/r#42 head=abc123 pushed=deadbeef %-%->', 1) ~= nil, 'header serialized')
P.ok(text:find('\n## a/b.go:42\n', 1, true) ~= nil, 'single-line heading')
P.ok(text:find('\n## a/b.go:10-15\n', 1, true) ~= nil, 'range heading')

local back = store.read(file)
P.eq(back.header.head, 'abc123', 'header head round-trips')
P.eq(back.header.pushed, 'deadbeef', 'header pushed round-trips')
P.eq(#back.entries, 2, 'two entries round-trip')
local e = store.find(back, 'a/b.go', 42)
P.eq(e and e.body, 'first\n\nsecond para', 'multi-paragraph body round-trips')
local r = store.find(back, 'a/b.go', 15, 10)
P.eq(r and r.start_line, 10, 'range start_line round-trips')

store.upsert(back, { path = 'a/b.go', line = 42, body = 'edited' })
P.eq(store.find(back, 'a/b.go', 42).body, 'edited', 'upsert replaces by key')
P.eq(#back.entries, 2, 'upsert did not duplicate')

store.upsert(back, { path = 'a/b.go', line = 42, body = '   \n ' })
P.eq(store.find(back, 'a/b.go', 42), nil, 'blank body deletes')
P.eq(#back.entries, 1, 'one entry left')

store.remove(back, 'a/b.go', 15, 10)
P.eq(#back.entries, 0, 'remove empties')

local fp1 = store.fingerprint({ { path = 'x', line = 1, body = 'a' }, { path = 'y', line = 2, body = 'b' } })
local fp2 = store.fingerprint({ { path = 'y', line = 2, body = 'b' }, { path = 'x', line = 1, body = 'a' } })
P.eq(fp1, fp2, 'fingerprint is order-independent')
P.ok(fp1 ~= store.fingerprint({ { path = 'x', line = 1, body = 'changed' } }), 'fingerprint changes with body')

P.eq(store.parse('').header.head, nil, 'empty text parses')
P.eq(#store.parse('# junk\n\nno headings').entries, 0, 'non-entry text ignored')

-- A doc with no repo yet must not lose head/pushed through serialize -> parse:
-- pushed is the fingerprint sync compares against.
local norepo = store.parse(store.serialize({ header = { head = 'abc', pushed = 'deadbeef' }, entries = {} }))
P.eq(norepo.header.repo, nil, 'header without repo stays nil')
P.eq(norepo.header.head, 'abc', 'header without repo keeps head')
P.eq(norepo.header.pushed, 'deadbeef', 'header without repo keeps pushed')

-- Hand-edited files: CRLF and stray trailing whitespace must not drop entries.
local crlf = store.parse('<!-- review: o/r#1 head=h pushed=p -->\r\n\r\n## a/b.go:9\r\n\r\nbody\r\n')
P.eq(#crlf.entries, 1, 'CRLF heading parses to one entry')
P.eq(crlf.entries[1] and crlf.entries[1].body, 'body', 'CRLF body has no stray CR')
P.eq(crlf.header.pushed, 'p', 'CRLF header parses')

local trailing = store.parse('## a/b.go:42 \n\nbody\n')
P.eq(#trailing.entries, 1, 'heading with trailing space parses to one entry')
P.eq(trailing.entries[1] and trailing.entries[1].body, 'body', 'trailing-space heading keeps its body')

local trailing_range = store.parse('## a/b.go:10-15  \n\nbody\n')
P.eq(trailing_range.entries[1] and trailing_range.entries[1].start_line, 10, 'trailing-space range heading parses')

-- One entry per anchor: a repeated heading must collapse, or find/upsert edit
-- one twin while serialize writes the other.
local dup = store.parse('## a/b.go:9\n\nfirst\n\n## a/b.go:9\n\nsecond\n')
P.eq(#dup.entries, 1, 'duplicate anchors collapse to one entry')
P.eq(dup.entries[1] and dup.entries[1].body, 'second', 'last heading wins')

-- A write that cannot land was silent: callers cleared the float, stamped the
-- header and reported success over a file that never changed. `afile` is a
-- regular file, so mkdir throws (E739) on the directory this path needs.
local afile = vim.fn.tempname()
vim.fn.writefile({ 'i am a file, not a directory' }, afile)
local wok, werr = store.write(afile .. '/x.md', { header = {}, entries = {} })
P.eq(wok, false, 'write under a regular file fails')
P.ok(type(werr) == 'string' and werr:find('cannot write', 1, true) ~= nil,
  '…with an error naming the file: ' .. tostring(werr))

-- …and a read-only file fails the same way, where mkdir succeeds and only
-- writefile refuses.
local ro = vim.fn.tempname() .. '/7.md'
vim.fn.mkdir(vim.fn.fnamemodify(ro, ':h'), 'p')
vim.fn.writefile({ '' }, ro)
vim.fn.setfperm(ro, 'r--r--r--')
local rok, rerr = store.write(ro, { header = {}, entries = {} })
vim.fn.setfperm(ro, 'rw-r--r--')
P.eq(rok, false, 'write to a read-only file fails')
P.ok(type(rerr) == 'string', '…with an error string: ' .. tostring(rerr))

local good = vim.fn.tempname() .. '/reviews/7.md'
local gok, gerr = store.write(good, { header = {}, entries = {} })
P.eq(gok, true, 'a write that lands returns true')
P.eq(gerr, nil, '…and no error')
P.eq(vim.fn.filereadable(good), 1, '…and the file is there')

P.done()
