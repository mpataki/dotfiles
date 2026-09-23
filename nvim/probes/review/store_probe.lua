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

P.done()
