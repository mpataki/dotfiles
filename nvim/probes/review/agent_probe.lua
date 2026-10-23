-- Agent-first review: a branch with no PR is reviewable, the draft follows the
-- checked-out branch, the GitHub gestures refuse without a PR, push refuses a
-- dirty commented file and asks before writing, and the hand-off (send/clear)
-- works off the draft file. Fake gh throughout; no network.
package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local gh = require('mpataki.review.gh')
local review = require('mpataki.review')
local sync = require('mpataki.review.sync')
local handoff = require('mpataki.review.handoff')

-- What the user is told: every gesture reports through vim.notify.
local notes = {}
local real_notify = vim.notify
vim.notify = function(msg, level, opts)
  notes[#notes + 1] = tostring(msg)
  return real_notify(msg, level, opts)
end
local function said_since(n, text)
  for i = n + 1, #notes do
    if notes[i]:find(text, 1, true) then return true end
  end
  return false
end

local function sh(argv, cwd)
  local r = vim.system(argv, { cwd = cwd, text = true }):wait()
  assert(r.code == 0, table.concat(argv, ' ') .. ': ' .. (r.stderr or ''))
  return vim.trim(r.stdout)
end

local calls, canned = F.fake_gh(gh)
local function json(t) return { code = 0, stdout = vim.json.encode(t), stderr = '' } end
local fx = F.repo()
local file = fx.root .. '/sub/dir/file.txt'
pr.clear_cache()
vim.cmd('edit ' .. vim.fn.fnameescape(file))
-- The draft lives under .git, which names no repo of its own: repo gestures
-- fired from it resolve through the cwd, as they do in a real session.
vim.fn.chdir(fx.root)

-- No PR (the fixture has no remote, gh fails): still a review.
local ctx, err = review.context()
P.ok(ctx ~= nil, 'no PR: context resolves: ' .. tostring(err))
P.eq(ctx and ctx.info.branch, 'feature', 'no PR: info carries the branch')
P.eq(ctx and ctx.file, store.path(ctx.info.common_dir, 'feature'), 'no PR: draft is the branch draft')

-- Line 1 is unchanged: still commentable.
store.write(ctx.file, { header = {}, entries = {
  { path = 'sub/dir/file.txt', line = 1, body = 'why is this here?' },
} })
P.eq(#store.read(ctx.file).entries, 1, 'draft written')

-- The GitHub gestures refuse before reaching gh.
local c0, n0 = #calls, #notes
sync.push(false)
sync.pull()
review.browse()
P.ok(said_since(n0, ':ReviewPush needs a PR; none for branch feature'), 'push refuses without a PR')
P.ok(said_since(n0, ':ReviewPull needs a PR'), 'pull refuses without a PR')
P.ok(said_since(n0, ':ReviewBrowse needs a PR'), 'browse refuses without a PR')
local gh_writes = 0
for i = c0 + 1, #calls do
  local a = table.concat(calls[i].argv, ' ')
  if a:find('-X', 1, true) then gh_writes = gh_writes + 1 end
end
P.eq(gh_writes, 0, 'no gh write without a PR')

-- Send: the message names the draft and how to read it.
local msg = handoff.message(ctx.file)
P.ok(msg:find(ctx.file, 1, true) ~= nil, 'send message names the draft path')
P.ok(msg:find('"## path:line"', 1, true) ~= nil, 'send message explains the headings')

-- Send refuses an empty draft and an unwritten draft buffer, before tmux.
local real_send = require('mpataki.ask').send
local sent = {}
require('mpataki.ask').send = function(text, cb) sent[#sent + 1] = text; cb(true, nil, { session = 's', window = '1', id = '%1' }) end
vim.cmd('edit ' .. vim.fn.fnameescape(ctx.file))
vim.api.nvim_buf_set_lines(0, -1, -1, false, { 'unsaved line' })
n0 = #notes
handoff.send()
P.ok(said_since(n0, 'unwritten changes'), 'send refuses an unwritten draft buffer')
P.eq(#sent, 0, 'nothing sent from an unwritten draft')
vim.cmd('edit!')
handoff.send()
P.eq(#sent, 1, 'send hands one message to ask')
P.eq(sent[1], msg, 'the message sent is the draft message')
require('mpataki.ask').send = real_send

-- Clear: confirm No keeps everything; Yes archives and empties.
vim.cmd('edit ' .. vim.fn.fnameescape(file))
local answer = false
sync.confirm = function() return answer end
handoff.clear()
P.eq(#store.read(ctx.file).entries, 1, 'clear answered No: draft untouched')
answer = true
handoff.clear()
P.eq(vim.fn.filereadable(ctx.file), 0, 'clear answered Yes: draft moved away')
local archived = vim.fn.glob(ctx.file:gsub('%.md$', '') .. '.*.md', false, true)
P.eq(#archived, 1, 'clear: one archive next to the draft')
P.eq(archived[1] and #store.read(archived[1]).entries, 1, 'clear: the archive holds the comments')
n0 = #notes
handoff.send()
P.ok(said_since(n0, 'no comments'), 'send after clear: nothing to send')

-- The draft follows the checkout: another branch, another draft.
sh({ 'git', 'checkout', '-q', '-b', 'feat/other' }, fx.root)
local octx = review.context()
P.eq(octx and octx.file, store.path(octx.info.common_dir, 'feat/other'), 'checkout: the new branch has its own draft')
P.ok(octx and octx.file:find('feat%2Fother.md', 1, true) ~= nil, 'checkout: branch slash percent-encoded')
sh({ 'git', 'checkout', '-q', 'feature' }, fx.root)
P.eq(review.context().file, ctx.file, 'checkout back: the original draft again')

-- Detached HEAD: review refuses, the PR-base surface (pr.info) still works.
sh({ 'git', 'checkout', '-q', '--detach' }, fx.root)
local dctx, derr = review.context()
P.eq(dctx, nil, 'detached: no review context')
P.ok(derr and derr:find('detached HEAD', 1, true) ~= nil, 'detached: says so: ' .. tostring(derr))
local dinfo = pr.info(fx.root)
P.ok(dinfo and dinfo.base_sha == fx.base_sha, 'detached: pr.info still finds the base (gS, overlay)')
sh({ 'git', 'checkout', '-q', 'feature' }, fx.root)

-- Push with a PR: dirty commented file refused; confirm No writes nothing.
local info = pr.info(fx.root)
info.number, info.head, info.url = 7, fx.head_sha, 'https://example.invalid/acme/w/pull/7'
ctx = review.context()
store.write(ctx.file, { header = {}, entries = {
  { path = 'sub/dir/file.txt', line = 5, body = 'in the hunk' },
} })
vim.fn.writefile({ 'dirty' }, file, 'a')
local asked = 0
sync.confirm = function() asked = asked + 1; return false end
c0, n0 = #calls, #notes
sync.push(false)
P.ok(said_since(n0, 'uncommitted changes: sub/dir/file.txt'), 'push refuses a dirty commented file')
P.eq(asked, 0, 'dirty refusal comes before the confirm')
P.eq(#calls - c0, 0, 'dirty refusal reaches no gh at all')
sh({ 'git', 'checkout', '--', 'sub/dir/file.txt' }, fx.root)
vim.cmd('edit!')

canned['user'] = json({ login = 'mpataki' })
canned['pulls/7/reviews'] = json({ {} }) -- no pending review of mine
canned['POST repos/{owner}/{repo}/pulls/7/reviews'] = json({ id = 501 })
local function writes_since(n)
  local w = 0
  for i = n + 1, #calls do
    local a = table.concat(calls[i].argv, ' ')
    if a:find('POST', 1, true) or a:find('DELETE', 1, true) then w = w + 1 end
  end
  return w
end

-- Clean tree, answer No: asked once, nothing written to GitHub.
local prompt
sync.confirm = function(m) asked = asked + 1; prompt = m; return false end
c0, n0 = #calls, #notes
sync.push(false)
P.eq(asked, 1, 'push asks before writing')
P.ok(prompt and prompt:find('Push 1 comment(s) as a PENDING review to acme/w#7?', 1, true) ~= nil,
  'the prompt names count and PR: ' .. tostring(prompt))
P.eq(writes_since(c0), 0, 'answer No: no POST/DELETE')
P.ok(said_since(n0, 'push cancelled; nothing sent'), 'answer No: says nothing was sent')

-- `!` skips the clobber guard, never the confirm.
asked = 0
sync.push(true)
P.eq(asked, 1, 'push! still asks')

-- Default answer is No: the real prompt with nothing typed returns false.
P.eq(vim.fn.confirm('probe', '&No\n&Yes', 1) == 2, false, 'confirm default is No')

-- Answer Yes: one POST.
sync.confirm = function() return true end
c0 = #calls
sync.push(false)
P.eq(writes_since(c0), 1, 'answer Yes: the pending review is created')

vim.notify = real_notify
P.done()
