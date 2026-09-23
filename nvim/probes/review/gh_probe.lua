package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local gh = require('mpataki.review.gh')

local calls, canned = F.fake_gh(gh)

local function last() return calls[#calls] end

canned['user'] = { code = 0, stdout = '{"login":"mpataki"}', stderr = '' }
P.eq(gh.login('/r'), 'mpataki', 'login parsed')
P.eq(last().opts.cwd, '/r', 'runs in repo root')

canned['pulls/7/comments'] = { code = 0, stdout = vim.json.encode({ {
  { id = 1, path = 'a.go', line = 3, start_line = vim.NIL, side = 'RIGHT', body = 'hi',
    user = { login = 'bob' }, in_reply_to_id = vim.NIL, html_url = 'u1', pull_request_review_id = 99 },
  { id = 2, path = 'a.go', line = vim.NIL, original_line = 8, side = 'LEFT', body = 'old',
    user = { login = 'amy' }, in_reply_to_id = 1, html_url = 'u2', pull_request_review_id = 99 },
} }), stderr = '' }
local threads = gh.threads('/r', 7)
P.eq(#threads, 2, 'two threads')
P.eq(threads[1].author, 'bob', 'author flattened')
P.eq(threads[1].start_line, nil, 'NIL start_line becomes nil')
P.eq(threads[2].line, 8, 'LEFT comment falls back to original_line')
P.eq(threads[2].in_reply_to_id, 1, 'reply id kept')
P.ok(vim.tbl_contains(last().argv, '--paginate'), 'threads paginate')

-- A PENDING review's comments only carry lines over GraphQL: REST answers
-- line/original_line/start_line/original_start_line/side all null for one.
-- Page 1 says hasNextPage, so the second comment only arrives if the cursor
-- is carried into a second query.
local function graphql_page(nodes, next_cursor)
  return { code = 0, stdout = vim.json.encode({ data = { node = { state = 'PENDING', comments = {
    nodes = nodes,
    pageInfo = { hasNextPage = next_cursor ~= nil, endCursor = next_cursor or vim.NIL },
  } } } }), stderr = '' }
end

canned['graphql -f query={ node(id: "R_pending7"'] = function(argv)
  if table.concat(argv, ' '):find('after: "CUR1"', 1, true) then
    return graphql_page({ { path = 'b.go', line = 20, startLine = 18, body = 'draft two' } })
  end
  return graphql_page({ { path = 'a.go', line = 3, startLine = vim.NIL, body = 'draft one' } }, 'CUR1')
end
canned['pulls/7/reviews'] = { code = 0, stdout = vim.json.encode({ {
  { id = 54, state = 'APPROVED', node_id = 'R_approved7', user = { login = 'mpataki' } },
  { id = 55, state = 'PENDING', node_id = 'R_pending7', user = { login = 'mpataki' } },
  { id = 56, state = 'PENDING', node_id = 'R_pendingsomeone', user = { login = 'someone' } },
} }), stderr = '' }
local c0 = #calls
local pending = gh.pending_review('/r', 7, 'mpataki')
P.eq(pending and pending.id, 55, 'finds my pending review only')
P.eq(pending and #pending.comments, 2, 'pending comments loaded')
P.eq(pending and pending.comments[1].line, 3, 'graphql line mapped')
P.eq(pending and pending.comments[1].body, 'draft one', 'graphql body mapped')
P.eq(pending and pending.comments[2].start_line, 18, 'range start kept')
local queries = {}
for i = c0 + 1, #calls do
  local argv = table.concat(calls[i].argv, ' ')
  if argv:find('graphql', 1, true) then table.insert(queries, argv) end
end
P.eq(#queries, 2, 'two graphql pages fetched')
-- REST would answer null for every line on a pending review's comments.
for i = c0 + 1, #calls do
  P.ok(not table.concat(calls[i].argv, ' '):find('/comments', 1, true),
    'pending comments never go through the REST comments endpoint')
end
P.ok(queries[1] and queries[1]:find('after: null', 1, true) ~= nil, 'first page asks for no cursor')
P.ok(queries[2] and queries[2]:find('after: "CUR1"', 1, true) ~= nil,
  'page 2 carries the endCursor from page 1: ' .. tostring(queries[2]))
P.ok(queries[1] and not queries[1]:find('--paginate', 1, true), 'graphql does not use --paginate')

canned['pulls/8/reviews'] = { code = 0, stdout = '[[]]', stderr = '' }
local none, err = gh.pending_review('/r', 8, 'mpataki')
P.eq(none, nil, 'no pending review → nil'); P.eq(err, nil, '…and no error')

canned['DELETE repos/{owner}/{repo}/pulls/7/reviews/55'] = { code = 0, stdout = '', stderr = '' }
P.ok(gh.delete_review('/r', 7, 55), 'delete ok')
P.ok(table.concat(last().argv, ' '):find('pulls/7/reviews/55', 1, true) ~= nil, 'delete targets review id')

canned['POST repos/{owner}/{repo}/pulls/7/reviews'] = { code = 0, stdout = '{"id":77}', stderr = '' }
local id = gh.create_pending('/r', 7, 'headsha', {
  { path = 'a.go', line = 3, body = 'x' },
  { path = 'b.go', line = 20, start_line = 18, body = 'y' },
})
P.eq(id, 77, 'create returns review id')
local sent = vim.json.decode(last().opts.stdin)
P.eq(sent.commit_id, 'headsha', 'commit_id sent')
P.eq(sent.event, nil, 'no event → pending')
P.eq(#sent.comments, 2, 'two comments')
P.eq(sent.comments[1].side, 'RIGHT', 'side RIGHT')
P.eq(sent.comments[1].start_line, nil, 'no start_line on single')
P.eq(sent.comments[2].start_line, 18, 'start_line on range')
P.eq(sent.comments[2].start_side, 'RIGHT', 'start_side on range')
P.ok(vim.tbl_contains(last().argv, '--input'), 'uses --input')

canned['POST repos/{owner}/{repo}/pulls/7/reviews'] = { code = 1, stdout = '', stderr = 'HTTP 422: Unprocessable\nmore' }
local bad, berr = gh.create_pending('/r', 7, 'headsha', { { path = 'a.go', line = 3, body = 'x' } })
P.eq(bad, nil, 'error returns nil')
P.ok(berr and berr:find('HTTP 422', 1, true) ~= nil, 'error carries first stderr line')
-- args lead with '-X POST', so naming args[1] would blame the flag and leave the
-- message ('gh api -X: HTTP 422') useless for finding the failing call.
P.ok(berr and berr:find('pulls/7/reviews', 1, true) ~= nil, 'error names the endpoint, not the -X flag')

-- --slurp wraps every page, including a page that is a single object rather than
-- a list. list_extend over a map appends nothing (its # is 0), so flattening
-- unconditionally would answer "empty" for a perfectly good response.
canned['gh api meta'] = { code = 0, stdout = '[{"a":1}]', stderr = '' }
local meta = gh.api('/r', { 'meta' }, { paginate = true })
P.eq(meta and #meta, 1, 'object page survives the slurp flatten')
P.eq(meta and meta[1] and meta[1].a, 1, '…with its fields intact')

-- GitHub nulls `user` on comments from deleted accounts. vim.NIL is truthy, so
-- `c.user and c.user.login` indexes a userdata and throws instead of yielding '?'.
canned['pulls/9/comments'] = { code = 0, stdout = '[[{"id":5,"path":"a.go","line":3,"body":null,"user":null,"html_url":"u5"}]]', stderr = '' }
local ghosts, gerr = gh.threads('/r', 9)
P.eq(gerr, nil, 'null user is not an error')
P.eq(ghosts and ghosts[1] and ghosts[1].author, '?', 'null user falls back to ?')
P.eq(ghosts and ghosts[1] and ghosts[1].body, '', 'null body falls back to empty string')

-- A login-less response must not read as success: pending_review would then match
-- no review, and sync would open a second pending review over the live one.
canned['user'] = { code = 0, stdout = '{}', stderr = '' }
local nologin, lerr = gh.login('/r')
P.eq(nologin, nil, 'missing login → nil')
P.ok(lerr ~= nil, '…and an error, not a silent nil')

-- A create that reports no review id must not read as "nothing happened": the
-- review may well exist server-side, and a silent nil,nil sends sync back to
-- create another one. vim.NIL is truthy, so an explicit null needs nilify too.
canned['POST repos/{owner}/{repo}/pulls/7/reviews'] = { code = 0, stdout = '{}', stderr = '' }
local noid, noiderr = gh.create_pending('/r', 7, 'headsha', { { path = 'a.go', line = 3, body = 'x' } })
P.eq(noid, nil, 'create with no id in response → nil')
P.ok(type(noiderr) == 'string', '…and an error string')
canned['POST repos/{owner}/{repo}/pulls/7/reviews'] = { code = 0, stdout = '{"id":null}', stderr = '' }
local nullid, nulliderr = gh.create_pending('/r', 7, 'headsha', { { path = 'a.go', line = 3, body = 'x' } })
P.eq(nullid, nil, 'create with null id → nil, not vim.NIL')
P.ok(type(nulliderr) == 'string', '…and an error string')

-- GitHub nulls `line` and `start_line` together once a comment goes outdated.
-- Without the original_start_line fallback a multi-line comment comes back as a
-- single line — in pending_review that is round-trip data loss.
canned['pulls/10/comments'] = { code = 0, stdout = vim.json.encode({ {
  { id = 3, path = 'a.go', line = vim.NIL, original_line = 8, start_line = vim.NIL,
    original_start_line = 5, side = 'RIGHT', body = 'stale range', user = { login = 'bob' } },
} }), stderr = '' }
local outdated = gh.threads('/r', 10)
P.eq(outdated and outdated[1] and outdated[1].line, 8, 'outdated thread line falls back')
P.eq(outdated and outdated[1] and outdated[1].start_line, 5, 'outdated thread start_line falls back too')

canned['pulls/10/reviews'] = { code = 0, stdout = vim.json.encode({ {
  { id = 60, state = 'PENDING', node_id = 'R_pending10', user = { login = 'mpataki' } },
} }), stderr = '' }
canned['graphql -f query={ node(id: "R_pending10"'] = graphql_page({
  { path = 'a.go', line = vim.NIL, originalLine = 8, startLine = vim.NIL, originalStartLine = 5,
    body = 'stale draft' },
})
local stale = gh.pending_review('/r', 10, 'mpataki')
P.eq(stale and stale.comments[1] and stale.comments[1].line, 8, 'outdated pending line falls back')
P.eq(stale and stale.comments[1] and stale.comments[1].start_line, 5, 'outdated pending start_line falls back')

-- An id-less pending review cannot be deleted or fetched; calling it "none"
-- would have sync create a second review alongside it.
canned['pulls/11/reviews'] = { code = 0, stdout = vim.json.encode({ {
  { state = 'PENDING', node_id = 'R_pending11', user = { login = 'mpataki' } },
} }), stderr = '' }
local idless, idlesserr = gh.pending_review('/r', 11, 'mpataki')
P.eq(idless, nil, 'id-less pending review → nil')
P.ok(type(idlesserr) == 'string', '…and an error, not "no pending review"')

-- Same for a node-id-less one: without it the comments cannot be fetched at
-- all, and "none" would have sync create a second review alongside it.
canned['pulls/12/reviews'] = { code = 0, stdout = vim.json.encode({ {
  { id = 61, state = 'PENDING', user = { login = 'mpataki' } },
} }), stderr = '' }
local nonode, nonodeerr = gh.pending_review('/r', 12, 'mpataki')
P.eq(nonode, nil, 'node-id-less pending review → nil')
P.ok(type(nonodeerr) == 'string' and nonodeerr:find('node_id', 1, true) ~= nil,
  '…and an error naming node_id: ' .. tostring(nonodeerr))

-- A graphql envelope with a null node (the review vanished between the two
-- calls) must be an error, not an empty comment list that a push would then
-- treat as "the server has nothing".
canned['pulls/13/reviews'] = { code = 0, stdout = vim.json.encode({ {
  { id = 62, state = 'PENDING', node_id = 'R_pending13', user = { login = 'mpataki' } },
} }), stderr = '' }
canned['graphql -f query={ node(id: "R_pending13"'] = { code = 0, stdout = '{"data":{"node":null}}', stderr = '' }
local gone, goneerr = gh.pending_review('/r', 13, 'mpataki')
P.eq(gone, nil, 'null graphql node → nil')
P.ok(type(goneerr) == 'string', '…and an error string')

P.done()
