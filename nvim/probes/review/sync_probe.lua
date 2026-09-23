-- :ReviewPush / :ReviewPull against a fake gh. Covers the guard *order* (every
-- refusal happens before anything destructive reaches the server), the pure
-- check_push contract, and pull overwriting the local draft from the server.
package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local gh = require('mpataki.review.gh')
local render = require('mpataki.review.render')
local review = require('mpataki.review')
local sync = require('mpataki.review.sync')

-- Keeps '-- INSERT --' and friends out of the headless transcript.
vim.o.showmode = false

-- vim.notify is nvim-notify here: assert through its history, never override
-- it. History is appended asynchronously, hence the waits.
local function history() return require('notify').history() end
local function mark() return #history() end
local function notes_since(n)
  local h, out = history(), {}
  for i = n + 1, #h do table.insert(out, table.concat(h[i].message, ' ')) end
  return table.concat(out, '\n')
end
local function wait_note(n, text)
  P.wait(1000, function() return notes_since(n):find(text, 1, true) ~= nil end)
  return notes_since(n)
end
local function level_of(n, text)
  for i = n + 1, #history() do
    local rec = history()[i]
    if table.concat(rec.message, ' '):find(text, 1, true) then return rec.level end
  end
end

local function sh(argv, cwd)
  local r = vim.system(argv, { cwd = cwd, text = true }):wait()
  assert(r.code == 0, table.concat(argv, ' ') .. ': ' .. (r.stderr or ''))
  return vim.trim(r.stdout)
end

-- Pretend the fixture repo is PR #7 by seeding pr's cache: no gh in probes.
local fx = F.repo()
pr.clear_cache()
local info = pr.info(fx.root)
info.number = 7
info.head = fx.head_sha
info.url = 'https://example.invalid/pr/7'

vim.cmd('edit ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/file.txt'))
local ctx = assert(review.context())

-- F.fake_gh appends to the table it returns, so watch a slice of it rather
-- than rebinding `calls` (which would leave the fake writing to the old one).
local calls, canned = F.fake_gh(gh)
local function calls_since(n)
  local out = {}
  for i = n + 1, #calls do table.insert(out, calls[i]) end
  return out
end
local function json(t) return { code = 0, stdout = vim.json.encode(t), stderr = '' } end
canned['user'] = json({ login = 'mpataki' })
canned['pulls/7/reviews'] = json({ {} })          -- no pending review
canned['POST repos/{owner}/{repo}/pulls/7/reviews'] = json({ id = 501 })
canned['DELETE repos/{owner}/{repo}/pulls/7/reviews/501'] = { code = 0, stdout = '', stderr = '' }
canned['pulls/7/comments'] = json({ { { id = 9, path = 'sub/dir/file.txt', line = 11, side = 'RIGHT',
  body = 'remote says hi', user = { login = 'bob' }, html_url = 'u', pull_request_review_id = 3 } } })

-- Pure guard checks -----------------------------------------------------------
local doc = { header = {}, entries = {} }
local ok, err = sync.check_push(ctx, doc, nil, fx.head_sha)
P.ok(not ok and err:find('no pending comments', 1, true), 'empty doc refused')

store.upsert(doc, { path = 'sub/dir/file.txt', line = 5, body = 'c1' })
ok, err = sync.check_push(ctx, doc, nil, 'othersha')
P.ok(not ok and err:find('HEAD', 1, true), 'head mismatch refused: ' .. tostring(err))

store.upsert(doc, { path = 'sub/dir/file.txt', line = 1, body = 'outside' })
ok, err = sync.check_push(ctx, doc, nil, fx.head_sha)
P.ok(not ok and err:find('sub/dir/file.txt:1', 1, true), 'out-of-diff entry named: ' .. tostring(err))
store.remove(doc, 'sub/dir/file.txt', 1)

-- A diff that *fails* (PR head not fetched) is not "no hunks": it must be its
-- own refusal naming the file and the head, never a throw from in_ranges(nil).
local badctx = { root = ctx.root, file = ctx.file,
  info = { base_sha = ctx.info.base_sha, head = ('0'):rep(40), number = 7 } }
local dok, derr = pcall(sync.check_push, badctx, doc, nil, badctx.info.head)
P.ok(dok, 'unfetched PR head does not throw')
ok, err = sync.check_push(badctx, doc, nil, badctx.info.head)
P.ok(not ok and err:find('sub/dir/file.txt', 1, true) and err:find('00000000', 1, true),
  'diff failure names the file and the head: ' .. tostring(err))

local pending = { id = 55, comments = { { path = 'sub/dir/file.txt', line = 5, body = 'edited in browser' } } }
doc.header.pushed = store.fingerprint(doc.entries)
ok, err = sync.check_push(ctx, doc, pending, fx.head_sha)
P.ok(not ok and err:find('clobber', 1, true), 'server drift refused: ' .. tostring(err))

pending.comments[1].body = 'c1'
ok, err = sync.check_push(ctx, doc, pending, fx.head_sha)
P.ok(ok, 'matching server fingerprint passes: ' .. tostring(err))

-- A range comment must sit *entirely* inside hunks: both ends can be in the
-- diff while the middle is not, and GitHub rejects the whole batch for it. The
-- shared fixture's 11-line file cannot express two separate hunks, so build one.
local fw = F.repo()
local wlines = {}
for i = 1, 30 do wlines[i] = 'w ' .. i end
vim.fn.writefile(wlines, fw.root .. '/wide.txt')
sh({ 'git', 'add', 'wide.txt' }, fw.root)
sh({ 'git', 'commit', '-q', '-m', 'wide' }, fw.root)
local wbase = sh({ 'git', 'rev-parse', 'HEAD' }, fw.root)
wlines[5] = 'w 5 changed'
wlines[25] = 'w 25 changed'
vim.fn.writefile(wlines, fw.root .. '/wide.txt')
sh({ 'git', 'commit', '-q', '-am', 'wide edits' }, fw.root)
local whead = sh({ 'git', 'rev-parse', 'HEAD' }, fw.root)
local wctx = { root = fw.root, file = fw.root .. '/unused.md',
  info = { base_sha = wbase, head = whead, number = 7 } }
ok, err = sync.check_push(wctx, { header = {},
  entries = { { path = 'wide.txt', start_line = 5, line = 25, body = 'spans the gap' } } }, nil, whead)
P.ok(not ok and err:find('wide.txt:5-25', 1, true), 'range bridging two hunks refused: ' .. tostring(err))
ok, err = sync.check_push(wctx, { header = {},
  entries = { { path = 'wide.txt', line = 25, body = 'inside' } } }, nil, whead)
P.ok(ok, 'line inside the second hunk passes: ' .. tostring(err))

-- Push end-to-end against the fake -------------------------------------------
-- The cheap local guards run before the network: an empty draft costs nothing
-- and reports its own reason even when gh is unreachable.
local m = mark()
local c0 = #calls
sync.push(false)
P.wait(200)
P.eq(#calls_since(c0), 0, 'refusing an empty draft never touches the network')
P.ok(wait_note(m, 'no pending comments'):find('no pending comments', 1, true) ~= nil,
  'empty draft refusal notified')
P.eq(level_of(m, 'no pending comments'), 'ERROR', 'refusals notify at ERROR')

store.write(ctx.file, doc)
c0 = #calls
m = mark()
sync.push(false)
P.wait(200)
local posted
for _, c in ipairs(calls_since(c0)) do
  if vim.tbl_contains(c.argv, 'POST') then posted = vim.json.decode(c.opts.stdin) end
end
P.ok(posted ~= nil, 'POST sent')
P.eq(posted and posted.commit_id, fx.head_sha, 'commit_id is PR head')
P.eq(posted and #posted.comments, 1, 'one comment posted')
local after = store.read(ctx.file)
P.eq(after.header.pushed, store.fingerprint(after.entries), 'header pushed updated')
P.eq(after.header.head, fx.head_sha, 'header head updated')
P.ok(wait_note(m, 'pushed'):find('example.invalid/pr/7', 1, true) ~= nil, 'PR URL printed')

-- Second push with a server pending review that matches: DELETE then POST.
canned['pulls/7/reviews'] = json({ { { id = 501, state = 'PENDING', user = { login = 'mpataki' } } } })
canned['pulls/7/reviews/501/comments'] = json({ { { path = 'sub/dir/file.txt', line = 5, start_line = vim.NIL, body = 'c1' } } })
c0 = #calls
sync.push(false)
P.wait(200)
local order = {}
for _, c in ipairs(calls_since(c0)) do
  if vim.tbl_contains(c.argv, 'DELETE') then table.insert(order, 'DELETE') end
  if vim.tbl_contains(c.argv, 'POST') then table.insert(order, 'POST') end
end
P.eq(table.concat(order, ','), 'DELETE,POST', 'replace = delete then create')

-- Drift on server + no bang: refused, no DELETE. With bang: proceeds.
canned['pulls/7/reviews/501/comments'] = json({ { { path = 'sub/dir/file.txt', line = 5, start_line = vim.NIL, body = 'browser edit' } } })
c0 = #calls
m = mark()
sync.push(false)
P.wait(200)
P.ok(wait_note(m, 'clobber'):find('clobber', 1, true) ~= nil, 'drift refused without bang')
local function deleted_since(n)
  for _, c in ipairs(calls_since(n)) do
    if vim.tbl_contains(c.argv, 'DELETE') then return true end
  end
  return false
end
P.ok(not deleted_since(c0), 'no DELETE on refusal')
c0 = #calls
sync.push(true)
P.wait(200)
P.ok(deleted_since(c0), 'bang overrides drift guard')

-- owner/repo comes off the PR url host-agnostically (GHE is not github.com).
info.url = 'https://ghe.example.invalid/acme/widgets/pull/7'
sync.push(true)
P.wait(200)
P.eq(store.read(ctx.file).header.repo, 'acme/widgets#7', 'header repo derived from a non-github.com url')
info.url = 'https://example.invalid/pr/7'

-- Pull: remote threads cached, pending section replaced from server ---------
-- The second server comment is one GitHub no longer anchors (line and
-- original_line both null): it has no heading to write and must not reach the
-- file — nor throw while store.key formats it.
canned['pulls/7/reviews/501/comments'] = json({ {
  { path = 'sub/dir/file.txt', line = 5, start_line = vim.NIL, body = 'from server' },
  { path = 'sub/dir/file.txt', line = vim.NIL, original_line = vim.NIL, start_line = vim.NIL, body = 'outdated' },
} })
m = mark()
sync.pull()
P.wait(200)
local threads = review.load_threads(ctx)
P.eq(#threads, 1, 'remote thread cached')
P.eq(threads[1].author, 'bob', 'thread author cached')
local pulled = store.read(ctx.file)
P.eq(#pulled.entries, 1, 'unanchored server comment dropped')
P.eq(pulled.entries[1].body, 'from server', 'pending section replaced from server')
P.eq(pulled.header.pushed, store.fingerprint(pulled.entries), 'pull sets pushed fingerprint to server state')
P.eq(#vim.api.nvim_buf_get_extmarks(0, render.ns, 0, -1, {}), 2, 'pull re-rendered pending + remote')

-- …and the fingerprint the clobber guard compares against drops the same
-- comment, or the next push refuses a review nobody touched.
local raw = assert(gh.pending_review(ctx.root, 7, 'mpataki'))
local cok, cres = pcall(sync.check_push, ctx, pulled, raw, fx.head_sha)
P.ok(cok, 'clobber fingerprint survives an unanchored server comment')
P.ok(cok and cres, 'a freshly pulled draft is pushable without a clobber warning')

-- No pending review on the server: the local pending section empties out, and
-- `pushed` records the fingerprint of *that*, so the next push is not "drift".
canned['pulls/7/reviews'] = json({ {} })
sync.pull()
P.wait(200)
local emptied = store.read(ctx.file)
P.eq(#emptied.entries, 0, 'pull with no server pending review empties the draft')
P.eq(emptied.header.pushed, store.fingerprint({}), 'pushed matches an empty list')
P.eq(#vim.api.nvim_buf_get_extmarks(0, render.ns, 0, -1, {}), 1, 'only the remote thread renders')

-- Other windows are re-rendered too, and a window holding a fileless buffer
-- (no repo, no context) must be skipped rather than take the loop down.
vim.cmd('split ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/file.txt'))
local fwin = vim.api.nvim_get_current_win()
local fbuf = vim.api.nvim_get_current_buf()
vim.cmd('vsplit | enew')
vim.api.nvim_set_current_win(fwin)
render.clear(fbuf)
local rok = pcall(sync.pull)
P.wait(200)
P.ok(rok, 'rerender skips a window with a fileless buffer')
P.eq(#vim.api.nvim_buf_get_extmarks(fbuf, render.ns, 0, -1, {}), 1, 'the review file buffer is re-rendered')
vim.cmd('only')

P.done()
