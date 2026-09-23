-- Push the local pending-comments file into a GitHub *pending* review (never
-- submitted from here), and pull remote threads + my pending review back.
-- Both directions are explicit overwrites; check_push stops a push that would
-- silently discard edits made to the pending review in the browser.
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local gh = require('mpataki.review.gh')
local render = require('mpataki.review.render')
local review = require('mpataki.review')

local M = {}

local function notify(msg, level)
  vim.notify('review: ' .. msg, level or vim.log.levels.INFO)
end

-- Every refusal ends here: nothing about a push is worth a silent no-op.
local function fail(msg)
  notify(msg, vim.log.levels.ERROR)
end

-- Bodies arrive from GitHub with CRLF endings; a notification wants one line.
local function first_line(body)
  return (((body or ''):gsub('\r', '')):match('^[^\n]*'))
end

local function short(sha)
  return (sha or '?'):sub(1, 8)
end

-- nil when git cannot answer (unborn branch, broken worktree); check_push turns
-- that into the refusal, so the guard order below holds for it too.
local function local_head(root)
  local r = pr.git(root, { 'rev-parse', 'HEAD' })
  if r.code ~= 0 then return nil end
  local sha = vim.trim(r.stdout)
  return sha ~= '' and sha or nil
end

-- GitHub nils both `line` and `original_line` on a pending comment whose anchor
-- the branch has moved out from under. There is no heading to write for one —
-- store.key would throw formatting a nil line — so both users of the server's
-- comment list drop them, or the fingerprint compared in check_push would not
-- match the list pull just wrote and every later push would read as drift.
local function split_anchored(comments)
  local kept, dropped = {}, {}
  for _, c in ipairs(comments or {}) do
    if c.path and type(c.line) == 'number' then
      table.insert(kept, c)
    else
      table.insert(dropped, c)
    end
  end
  return kept, dropped
end

local function anchored(comments)
  return (split_anchored(comments))
end

-- Every line of a range must sit in a hunk, not just its ends: GitHub rejects a
-- range that bridges the gap between two hunks, and the whole batch with it.
-- Same rule review.comment applies when the entry is made; re-checked here
-- because the file is hand-editable between the two.
local function line_outside(ranges, entry)
  for l = entry.start_line or entry.line, entry.line do
    if not pr.in_ranges(ranges, l) then return l end
  end
  return nil
end

-- ok, err. Pure enough to exercise without gh: `pending` (my pending review as
-- the server has it, or nil to skip the clobber guard) and `head` (the local
-- checkout's sha) are arguments. `ranges` is an optional path -> ranges cache
-- so push can run the local guards before it talks to the network and the
-- clobber guard after, without shelling out to git twice.
function M.check_push(ctx, doc, pending, head, ranges)
  if #doc.entries == 0 then
    return false, 'no pending comments in ' .. ctx.file
  end
  if not head then
    return false, ('cannot read HEAD in %s; is the branch unborn?'):format(ctx.root)
  end
  if head ~= ctx.info.head then
    return false, ('local HEAD %s ≠ PR head %s; push or pull the branch first')
      :format(short(head), short(ctx.info.head))
  end
  -- A backwards range is not just invalid to GitHub: `for l = start, line`
  -- never runs for it, so it would slip the diff guard below untouched and
  -- reach the DELETE. Hand-editing the file is how one gets here.
  for _, e in ipairs(doc.entries) do
    if e.start_line and e.start_line > e.line then
      return false, ('%s runs backwards (start line after end line); fix the heading in %s')
        :format(store.key(e), ctx.file)
    end
  end
  ranges = ranges or {}
  for _, e in ipairs(doc.entries) do
    if ranges[e.path] == nil then
      local r, derr = pr.diff_ranges(ctx.root, ctx.info.base_sha, ctx.info.head, e.path)
      -- A diff that failed is not "no hunks": blaming the comment would send
      -- the user editing a file when the fix is to fetch the PR branch.
      if not r then
        return false, ('cannot diff %s against PR head %s: %s — fetch the PR branch?')
          :format(e.path, short(ctx.info.head), derr or 'git diff failed')
      end
      ranges[e.path] = r
    end
    local bad = line_outside(ranges[e.path], e)
    if bad then
      return false, ('%s is outside the PR diff (line %d); GitHub would reject the whole batch — move it into a hunk or delete it from %s')
        :format(store.key(e), bad, ctx.file)
    end
  end
  if pending and store.fingerprint(anchored(pending.comments)) ~= (doc.header or {}).pushed then
    return false, 'pending review on GitHub differs from what was last pushed; :ReviewPull to take theirs, or :ReviewPush! to clobber'
  end
  return true, nil
end

-- owner/repo off the PR url, host-agnostically: a GitHub Enterprise url is not
-- on github.com, and stamping '?' there would put a wrong repo in the file.
-- Header text only — nothing keys off it — so an unparseable url just drops it.
local function repo_tag(info)
  local repo = info.url and info.url:match('^https?://[^/]+/(.-)/pull/%d')
  return (repo or '') .. '#' .. tostring(info.number)
end

-- The header records which server state `entries` corresponds to. pushed is
-- always the fingerprint of what is in the doc *now*, so the clobber guard
-- compares like with like on the next push.
local function stamp(doc, ctx)
  doc.header = doc.header or {}
  doc.header.repo = repo_tag(ctx.info)
  doc.header.head = ctx.info.head
  doc.header.pushed = store.fingerprint(doc.entries)
end

-- The comments file is an ordinary buffer. Reading it off disk while that
-- buffer holds unwritten edits would push the *previous* draft and report
-- success, which is the one failure mode a push must never have.
local function unsaved(ctx)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
      and vim.api.nvim_buf_get_name(buf) == ctx.file
      and vim.bo[buf].modified then
      return true
    end
  end
  return false
end

-- Push and pull rewrite the comments file under whatever is displaying it; an
-- open, unmodified buffer would otherwise keep showing the pre-push draft.
local function reload_file_buffers()
  vim.cmd('checktime')
end

-- current_context falls back to nvim's cwd, which can name a different repo
-- than the buffer on screen (the comments file of *another* repo resolves to no
-- repo of its own, so the fallback takes over). Acting on a PR the user is not
-- looking at is silent and unrecoverable, so refuse instead of guessing.
local function foreign_buffer(ctx, command)
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then return nil end -- a scratch buffer names no repo to disagree with
  -- Only a real path on disk can disagree with the repo we resolved. A scheme
  -- buffer (diffview:///panels/1, term://, oil://, neo-tree) has a name but no
  -- path, and those are exactly the buffers current_context exists to serve —
  -- refusing them would break the gesture instead of guarding it.
  local real = vim.uv.fs_realpath(name)
  if not real then return nil end
  if name == ctx.file or real == ctx.file then return nil end
  if real:sub(1, #ctx.root + 1) == ctx.root .. '/' then return nil end
  return ('current buffer belongs to another repo; %s from a file in %s or its comments file')
    :format(command, ctx.root)
end

-- Redraw every window on a file belonging to this review. One buffer can hold
-- several windows (render replaces the whole namespace, so once is enough), and
-- a window can hold a buffer with no file and no context at all.
local function rerender(ctx)
  local doc = store.read(ctx.file)
  local threads = review.load_threads(ctx)
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if not seen[buf] and vim.api.nvim_buf_is_valid(buf) then
      seen[buf] = true
      local bctx = review.context(buf)
      if bctx and bctx.file == ctx.file then
        render.render(buf, bctx.relpath, doc.entries, threads)
      end
    end
  end
end

-- :ReviewPush[!]. bang skips only the clobber guard.
function M.push(bang)
  -- current_context, not context: a push is a repo gesture, and the most likely
  -- buffer to fire it from is the comments file itself, which has no repo of
  -- its own (it lives under .git).
  local ctx, err = review.current_context()
  if not ctx then return fail(err) end
  local wrong = foreign_buffer(ctx, ':ReviewPush')
  if wrong then return fail(wrong) end
  if unsaved(ctx) then
    return fail(('%s has unwritten changes: write the comments file first (:w)'):format(ctx.file))
  end
  local doc = store.read(ctx.file)

  -- Local guards first, before any network call: an empty draft or a stale
  -- checkout costs nothing to refuse and must report its own reason even when
  -- gh is unreachable. Guard order is the one in check_push either way.
  local head = local_head(ctx.root)
  local ranges = {}
  local ok, cerr = M.check_push(ctx, doc, nil, head, ranges)
  if not ok then return fail(cerr) end

  local login, lerr = gh.login(ctx.root)
  if not login then return fail(lerr) end
  -- nil, nil is "no pending review of mine"; nil, err is one I must not step on.
  local pending, perr = gh.pending_review(ctx.root, ctx.info.number, login)
  if perr then return fail(perr) end

  if pending and not bang then
    local dok, derr = M.check_push(ctx, doc, pending, head, ranges)
    if not dok then return fail(derr) end
  end

  -- Nothing destructive until every guard has passed: the DELETE is the point
  -- of no return for whatever the browser has in that review.
  if pending then
    local dok, derr = gh.delete_review(ctx.root, ctx.info.number, pending.id)
    if not dok then return fail(derr) end
  end
  local id, ierr = gh.create_pending(ctx.root, ctx.info.number, ctx.info.head, doc.entries)
  if not id then return fail(ierr) end

  stamp(doc, ctx)
  store.write(ctx.file, doc)
  reload_file_buffers()
  notify(('pushed %d comment(s) as pending review %s — %s')
    :format(#doc.entries, tostring(id), ctx.info.url or '(no url)'))
end

-- :ReviewPull. Overwrites both local caches from the server.
function M.pull()
  local ctx, err = review.current_context()
  if not ctx then return fail(err) end
  local wrong = foreign_buffer(ctx, ':ReviewPull')
  if wrong then return fail(wrong) end

  local login, lerr = gh.login(ctx.root)
  if not login then return fail(lerr) end
  local pending, perr = gh.pending_review(ctx.root, ctx.info.number, login)
  if perr then return fail(perr) end

  local threads, terr = gh.threads(ctx.root, ctx.info.number)
  if not threads then return fail(terr) end
  -- My own pending comments come back through pending_review and render as
  -- pending; leaving them here too would draw every one of them twice.
  if pending then
    threads = vim.tbl_filter(function(t) return t.review_id ~= pending.id end, threads)
  end
  vim.fn.mkdir(vim.fn.fnamemodify(ctx.remote_file, ':h'), 'p')
  vim.fn.writefile({ vim.json.encode(threads) }, ctx.remote_file)

  local doc = store.read(ctx.file)
  local comments, dropped = split_anchored(pending and pending.comments)
  doc.entries = comments
  stamp(doc, ctx)
  store.write(ctx.file, doc)
  reload_file_buffers()

  rerender(ctx)
  notify(('pulled %d thread(s), %d pending comment(s)'):format(#threads, #doc.entries))
  -- Dropping a comment loses text the user wrote in the browser, so say which
  -- ones: they are gone from the file and cannot be pushed back.
  if #dropped > 0 then
    local lines = { ('%d pending comment(s) GitHub no longer anchors to a line:'):format(#dropped) }
    for _, c in ipairs(dropped) do
      table.insert(lines, ('dropped unanchored pending comment %s: %s')
        :format(c.path or '?', first_line(c.body)))
    end
    notify(table.concat(lines, '\n'), vim.log.levels.WARN)
  end
end

return M
