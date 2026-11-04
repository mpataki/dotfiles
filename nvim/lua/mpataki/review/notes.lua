-- The reading side of a review: see what is on a line in full (:ReviewPeek),
-- and move an entry between private note and review comment (:ReviewFlip).
-- Authoring a note is review.comment with kind = 'note'; the float, the store
-- and the render are shared, so a note is a comment that never leaves home.
local review = require('mpataki.review')
local store = require('mpataki.review.store')

local M = {}

local function notify_err(msg)
  vim.notify('review: ' .. msg, vim.log.levels.ERROR)
end

local function covers(item, line)
  if type(item.line) ~= 'number' then return false end
  local from = type(item.start_line) == 'number' and item.start_line or item.line
  return line >= from and line <= item.line
end

-- Markdown for every comment covering `line` of `relpath`: pending, then notes,
-- then remote threads — the stub's order, so the float reads like the line.
-- Covering, not ending on: the stub sits on the end line only, and the peek
-- is how a range's comment is read from anywhere inside it. Empty when the
-- line carries nothing.
function M.lines(relpath, line, entries, threads)
  local out = {}
  local function add(heading, body)
    if #out > 0 then vim.list_extend(out, { '', '---', '' }) end
    table.insert(out, heading)
    table.insert(out, '')
    vim.list_extend(out, vim.split(vim.trim(((body or ''):gsub('\r', ''))), '\n', { plain = true }))
  end
  for _, want_note in ipairs({ false, true }) do
    for _, e in ipairs(entries or {}) do
      if e.path == relpath and store.is_note(e) == want_note and covers(e, line) then
        add(('**%s** `%s`'):format(want_note and 'note' or 'pending', store.key(e)), e.body)
      end
    end
  end
  for _, t in ipairs(threads or {}) do
    if t.path == relpath and t.side ~= 'LEFT' and covers(t, line) then
      add(('**@%s** `%s`'):format(t.author or '?', store.key(t)), t.body)
    end
  end
  return out
end

-- open_floating_preview closes the float on the next cursor move and focuses
-- it on a second press (focus_id), which is the whole interaction wanted:
-- read, then keep reading the code.
function M.peek()
  local ctx, err = review.context()
  if not ctx then return notify_err(err) end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local doc = store.read(ctx.file)
  local lines = M.lines(ctx.relpath, line, doc.entries, review.load_threads(ctx))
  if #lines == 0 then return vim.notify('review: nothing on this line') end
  vim.lsp.util.open_floating_preview(lines, 'markdown', {
    border = 'rounded',
    focus_id = 'mpataki_review_peek',
    max_width = 80,
  })
end

-- The innermost entry under the cursor, of either kind. A note and a review on
-- the very same anchor is the one case flip refuses (store.flip): there is no
-- right answer for which of them should become the other.
function M.flip()
  local bufnr = vim.api.nvim_get_current_buf()
  local ctx, err = review.context(bufnr)
  if not ctx then return notify_err(err) end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local doc = store.read(ctx.file)
  local e = store.covering(doc, ctx.relpath, line)
  if not e then return notify_err('no note or comment on this line') end
  local ok, res = store.flip(doc, e)
  if not ok then return notify_err(res) end
  local wok, werr = store.write(ctx.file, doc)
  if not wok then return notify_err(werr) end
  review.render_buf(bufnr, ctx)
  vim.notify(('review: %s is now a %s'):format(store.key(e),
    res == 'note' and 'private note' or 'review comment (pushed with the next :ReviewPush)'))
end

return M
