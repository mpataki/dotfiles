-- Pending review comments as a markdown file. The file is the source of truth
-- for the local draft; the capture float and push/pull read and write it.
-- Format:
--   <!-- review: owner/repo#N head=<sha> pushed=<fingerprint> -->
--   ## path:line          (or ## path:start-end)
--   ## path:line [note]   a private note: never pushed to GitHub
--   body until next "## "
-- An untagged heading is a review comment, so drafts written before notes
-- existed read back unchanged.
local M = {}

-- 'review' (pushed to GitHub, addressed by the agent) or 'note' (mine: what I
-- understood while reading; the agent checks it, GitHub never sees it).
function M.kind(entry)
  return entry.kind == 'note' and 'note' or 'review'
end

function M.is_note(entry) return M.kind(entry) == 'note' end

function M.reviews(entries)
  return vim.tbl_filter(function(e) return not M.is_note(e) end, entries or {})
end

-- The one-line form of a body, for a notification or a quickfix entry. Trimmed
-- and CR-free because the three sources disagree: the comments file is
-- hand-edited, git and gh write to stderr, and GitHub hands back bodies with
-- CRLF endings (a trailing '\r' renders as a literal '^M').
function M.first_line(s)
  return (vim.trim(s or ''):gsub('\r', ''):match('^[^\n]*'))
end

-- One draft per branch. Anything outside [%w._-] is percent-encoded so
-- `feat/x` and `feat%2Fx` can never share a file (as `/` → `__` would let
-- `a/b` and `a__b` do).
function M.slug(branch)
  return (branch:gsub('[^%w%._%-]', function(c) return ('%%%02X'):format(c:byte()) end))
end

function M.path(common_dir, branch)
  return common_dir .. '/reviews/' .. M.slug(branch) .. '.md'
end

function M.remote_path(common_dir, branch)
  return common_dir .. '/reviews/' .. M.slug(branch) .. '.remote.json'
end

function M.key(entry)
  if entry.start_line then
    return ('%s:%d-%d'):format(entry.path, entry.start_line, entry.line)
  end
  return ('%s:%d'):format(entry.path, entry.line)
end

-- repo is %S* (not %S+): serialize writes every field every time, so a doc with
-- no repo yet emits a double space here — matching %S+ would reject the line and
-- silently drop head/pushed, and pushed is the fingerprint sync compares against.
local function parse_header(line)
  local repo, head, pushed = line:match('^<!%-%- review: (%S*) head=(%S*) pushed=(%S*) %-%->')
  if not repo then return {} end
  local function some(v) return v ~= '' and v or nil end
  return { repo = some(repo), head = some(head), pushed = some(pushed) }
end

-- %s*$ because this file is hand-edited: a heading with a stray trailing space
-- must still anchor its entry rather than dissolve the comment into nothing.
local function parse_heading(line)
  local kind
  local bare = line:match('^(.-)%s+%[note%]%s*$')
  if bare then line, kind = bare, 'note' end
  local path, a, b = line:match('^## (.-):(%d+)%-(%d+)%s*$')
  if path then return { path = path, start_line = tonumber(a), line = tonumber(b), kind = kind } end
  path, a = line:match('^## (.-):(%d+)%s*$')
  if path then return { path = path, line = tonumber(a), kind = kind } end
  return nil
end

function M.parse(text)
  local doc = { header = {}, entries = {} }
  local current, body = nil, {}

  -- One entry per anchor: a hand-edited file can repeat a heading, and keeping
  -- both would let find/upsert edit one twin while serialize writes the other.
  -- Last heading wins; the entry keeps the position of its first occurrence.
  local function flush()
    if current then
      current.body = vim.trim(table.concat(body, '\n'))
      local _, i = M.find(doc, current.path, current.line, current.start_line, current.kind)
      if i then doc.entries[i] = current else table.insert(doc.entries, current) end
    end
    current, body = nil, {}
  end

  for line in (text .. '\n'):gmatch('(.-)\n') do
    line = line:gsub('\r$', '') -- tolerate CRLF files
    local heading = parse_heading(line)
    if heading then
      flush()
      current = heading
    elseif not current and line:match('^<!%-%- review:') then
      doc.header = parse_header(line)
    elseif current then
      table.insert(body, line)
    end
  end
  flush()
  return doc
end

function M.serialize(doc)
  local h = doc.header or {}
  local out = {
    ('<!-- review: %s head=%s pushed=%s -->'):format(h.repo or '', h.head or '', h.pushed or ''),
    '',
  }
  for _, e in ipairs(doc.entries) do
    table.insert(out, '## ' .. M.key(e) .. (M.is_note(e) and ' [note]' or ''))
    table.insert(out, '')
    table.insert(out, e.body)
    table.insert(out, '')
  end
  return table.concat(out, '\n') .. '\n'
end

function M.read(file)
  if vim.fn.filereadable(file) ~= 1 then
    return { header = {}, entries = {} }
  end
  return M.parse(table.concat(vim.fn.readfile(file), '\n'))
end

-- ok, err. A write that cannot land (a read-only .git, a full disk, a path
-- whose parent is a regular file) used to be silent, and every caller went on
-- to report success and clear the draft the user just typed. mkdir *throws*
-- (E739) where writefile only returns non-zero, so both shapes are caught.
function M.write(file, doc)
  local mkok = pcall(vim.fn.mkdir, vim.fn.fnamemodify(file, ':h'), 'p')
  if not mkok then return false, 'cannot write ' .. file end
  local wok, res = pcall(vim.fn.writefile, vim.split(M.serialize(doc), '\n'), file)
  if not wok or res ~= 0 then return false, 'cannot write ' .. file end
  return true, nil
end

-- Identity is anchor *and* kind: a note and a review comment can sit on the
-- same lines ("what this does" next to "rename this"), and pull replaces only
-- the review half without ever colliding with a note.
function M.find(doc, path, line, start_line, kind)
  local want = M.key({ path = path, line = line, start_line = start_line })
  kind = M.kind({ kind = kind })
  for i, e in ipairs(doc.entries) do
    if M.key(e) == want and M.kind(e) == kind then return e, i end
  end
  return nil, nil
end

-- The entry a cursor-line gesture should reopen: the pending comment on `path`
-- whose [start_line, line] span contains `line`. Innermost wins, so a comment
-- nested inside another is still reachable; equal spans prefer the one ending on
-- the cursor, then file order, so the answer never depends on table order.
-- `kind` nil considers every entry; otherwise only that kind.
function M.covering(doc, path, line, kind)
  local best, best_span = nil, nil
  for _, e in ipairs((doc or {}).entries or {}) do
    if e.path == path and type(e.line) == 'number' and (kind == nil or M.kind(e) == kind) then
      local from = type(e.start_line) == 'number' and e.start_line or e.line
      if line >= from and line <= e.line then
        local span = e.line - from
        local ends_here = e.line == line
        if not best
          or span < best_span
          or (span == best_span and ends_here and best.line ~= line) then
          best, best_span = e, span
        end
      end
    end
  end
  return best
end

function M.remove(doc, path, line, start_line, kind)
  local _, i = M.find(doc, path, line, start_line, kind)
  if i then table.remove(doc.entries, i) end
end

function M.upsert(doc, entry)
  local body = vim.trim(entry.body or '')
  local _, i = M.find(doc, entry.path, entry.line, entry.start_line, entry.kind)
  if body == '' then
    if i then table.remove(doc.entries, i) end
    return
  end
  local e = { path = entry.path, line = entry.line, start_line = entry.start_line, body = body,
    kind = M.is_note(entry) and 'note' or nil }
  if i then doc.entries[i] = e else table.insert(doc.entries, e) end
end

-- Note <-> review, in place (file position kept). ok, err: refused when the
-- other kind already holds this anchor — merging two bodies is a judgment call
-- for a human, and overwriting either loses text.
function M.flip(doc, entry)
  local want = M.is_note(entry) and 'review' or 'note'
  if M.find(doc, entry.path, entry.line, entry.start_line, want) then
    return false, ('%s already has a %s; merge them by hand (:ReviewOpen)'):format(M.key(entry), want)
  end
  local e, i = M.find(doc, entry.path, entry.line, entry.start_line, entry.kind)
  if not i then return false, M.key(entry) .. ' is not in the draft' end
  e.kind = want == 'note' and 'note' or nil
  return true, want
end

-- Over review comments only: it is compared against what GitHub holds, and
-- GitHub never holds a note. Adding or editing a note must not read as drift.
function M.fingerprint(entries)
  local parts = {}
  for _, e in ipairs(M.reviews(entries)) do
    table.insert(parts, M.key(e) .. ':' .. vim.trim(e.body or ''))
  end
  table.sort(parts)
  return vim.fn.sha256(table.concat(parts, '\n'))
end

return M
