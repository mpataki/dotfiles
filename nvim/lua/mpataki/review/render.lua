-- Draws pending comments, notes and remote threads as a one-line stub
-- right-aligned on their anchor's end line (the body is one keypress away, in
-- peek.lua), a background tint on every line they cover, and fills the
-- quickfix list. The stub replaced virtual lines under the anchor: a full body
-- pushed the code down, and a review of any size read as prose with code in
-- it rather than the other way round. Pure
-- presentation: no git, no gh, no file IO — store is required for its pure
-- one-line-body helper, nothing else.
local store = require('mpataki.review.store')

local M = {}

M.ns = vim.api.nvim_create_namespace('mpataki_review')

-- Declared in a function and re-run on ColorScheme: ':colorscheme' runs
-- ':highlight clear', which re-applies a *default* link but does not restore a
-- default group defined by literal attributes — ReviewPendingRange's bg is gone
-- after a theme switch without this. `default = true` still earns its place: it
-- leaves an override of any of these groups standing. Load order does not matter.
--
-- The ranges tint the whole line rather than set a sign: the sign column has one
-- slot and mini.diff owns it. The pending bg was picked against catppuccin mocha;
-- CursorLine is a theme's own "this row is spoken for" wash, so remote threads
-- borrow it.
local function declare_hl()
  vim.api.nvim_set_hl(0, 'ReviewPending', { default = true, link = 'DiagnosticVirtualTextWarn' })
  vim.api.nvim_set_hl(0, 'ReviewRemote', { default = true, link = 'Comment' })
  vim.api.nvim_set_hl(0, 'ReviewPendingRange', { default = true, bg = '#2b2a1c' })
  vim.api.nvim_set_hl(0, 'ReviewRemoteRange', { default = true, link = 'CursorLine' })
  vim.api.nvim_set_hl(0, 'ReviewNote', { default = true, link = 'DiagnosticVirtualTextInfo' })
  vim.api.nvim_set_hl(0, 'ReviewNoteRange', { default = true, bg = '#1c2a2e' })
end

declare_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = declare_hl })

-- Display columns the summary may take, prefix excluded. Past it the stub
-- would start eating the code it sits beside.
M.SUMMARY_WIDTH = 50

-- The stub's text: first line of the body, clipped by display width (an author
-- or a body can carry multi-byte characters), with '…' whenever anything was
-- left out — a clipped line or further lines — so a stub never passes for the
-- whole comment. store.first_line strips the CR GitHub's CRLF bodies carry,
-- which nvim would otherwise draw as a literal '^M'.
function M.summary(body)
  local text = vim.trim(((body or ''):gsub('\r', '')))
  local first = store.first_line(text)
  local more = #first < #text
  if vim.fn.strdisplaywidth(first) > M.SUMMARY_WIDTH then
    first = vim.fn.strcharpart(first, 0, M.SUMMARY_WIDTH - 1)
    while vim.fn.strdisplaywidth(first) > M.SUMMARY_WIDTH - 1 do
      first = vim.fn.strcharpart(first, 0, vim.fn.strchars(first) - 1)
    end
    more = true
  end
  return more and (first .. '…') or first
end

local function valid_line(buf, line)
  return type(line) == 'number' and line >= 1 and line <= vim.api.nvim_buf_line_count(buf)
end

-- The stub sits on the *end* line only, so a multi-line comment reads as a
-- comment on that one line. Tinting every covered line is what makes the range
-- visible as a range. The low priority is load-bearing: mini.diff paints changed
-- lines with its own line background, and that git signal must win where the two
-- overlap. Lines outside the buffer draw nothing.
local function range_tint(buf, start_line, line, hl)
  if type(line) ~= 'number' then return end
  local last = vim.api.nvim_buf_line_count(buf)
  local from = type(start_line) == 'number' and start_line or line
  for l = math.max(from, 1), math.min(line, last) do
    vim.api.nvim_buf_set_extmark(buf, M.ns, l - 1, 0, { line_hl_group = hl, priority = 50 })
  end
end

function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
end

-- One stub mark per end line, holding every comment that ends there: two
-- right_align marks on one line would be laid side by side by nvim anyway, but
-- one mark keeps their order (pending, note, remote; then input order) ours.
-- `hl` is a chunk highlight list, not one group: the range tint supplies the
-- background and the fg group sits on top of it.
function M.render(buf, relpath, entries, threads)
  M.clear(buf)
  local stubs, order = {}, {}
  local function add(line, start_line, text, range_hl, fg_hl)
    -- Tint first: a range whose tail runs past EOF still tints the lines that
    -- exist; only the stub needs a real end line to sit on.
    range_tint(buf, start_line, line, range_hl)
    if not valid_line(buf, line) then return end
    if not stubs[line] then stubs[line] = {}; table.insert(order, line) end
    local chunks = stubs[line]
    if #chunks > 0 then table.insert(chunks, { '  ', range_hl }) end
    table.insert(chunks, { text, { range_hl, fg_hl } })
  end
  for _, e in ipairs(entries or {}) do
    if e.path == relpath and not store.is_note(e) then
      add(e.line, e.start_line, '[pending] ' .. M.summary(e.body), 'ReviewPendingRange', 'ReviewPending')
    end
  end
  for _, e in ipairs(entries or {}) do
    if e.path == relpath and store.is_note(e) then
      add(e.line, e.start_line, '[note] ' .. M.summary(e.body), 'ReviewNoteRange', 'ReviewNote')
    end
  end
  for _, t in ipairs(threads or {}) do
    if t.path == relpath and t.side ~= 'LEFT' then
      add(t.line, t.start_line, '@' .. t.author .. ': ' .. M.summary(t.body), 'ReviewRemoteRange', 'ReviewRemote')
    end
  end
  for _, line in ipairs(order) do
    vim.api.nvim_buf_set_extmark(buf, M.ns, line - 1, 0, {
      virt_text = stubs[line],
      virt_text_pos = 'right_align',
      hl_mode = 'combine',
    })
  end
end

-- A trailing slash would build '/root//a.go', which nvim keeps as a buffer
-- distinct from '/root/a.go': jumping from the quickfix list would open a
-- second buffer for the same file, with none of the review's extmarks in it.
local function join(root, path)
  return ((root or ''):gsub('/+$', '')) .. '/' .. path
end

function M.quickfix(root, entries, threads)
  local items = {}
  local function add(path, line, text)
    -- gh.threads leaves `path` nil when GitHub reports a comment without one;
    -- such an item has nowhere to jump to and would throw while being built.
    if not path then return end
    table.insert(items, { filename = join(root, path), lnum = line or 1, text = text })
  end
  for _, e in ipairs(entries or {}) do
    add(e.path, e.line, (store.is_note(e) and '[note] ' or '[pending] ') .. store.first_line(e.body))
  end
  for _, t in ipairs(threads or {}) do
    add(t.path, t.line, '@' .. t.author .. ': ' .. store.first_line(t.body))
  end
  vim.fn.setqflist({}, ' ', { title = 'PR review comments', items = items })
end

return M
