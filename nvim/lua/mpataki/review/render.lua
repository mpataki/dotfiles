-- Draws pending and remote comments as virtual lines under their anchor line,
-- a background tint on every line they cover, and fills the quickfix list. Pure
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
end

declare_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = declare_hl })

-- GitHub returns comment bodies with CRLF endings. Splitting on '\n' alone
-- leaves a trailing '\r', and nvim transliterates that into a literal '^M' at
-- the end of every rendered line.
local function body_lines(body)
  local text = ((body or ''):gsub('\r', ''))
  return vim.split(text, '\n', { plain = true })
end

-- `hl` is a chunk highlight list, not one group: the range tint supplies the
-- background and the fg group sits on top of it, so the comment block reads as
-- part of the range it belongs to.
local function virt_lines(prefix, body, hl)
  -- Display width, not #prefix: an author name can carry multi-byte characters,
  -- so byte-length padding pushes continuation lines out of alignment.
  local indent = string.rep(' ', vim.fn.strdisplaywidth(prefix))
  local lines = {}
  for i, l in ipairs(body_lines(body)) do
    table.insert(lines, { { (i == 1 and prefix or indent) .. l, hl } })
  end
  return lines
end

-- Sole gate on anchor validity. `line` is nil whenever GitHub nils both `line`
-- and `original_line` on an outdated comment, and one such entry must not throw
-- partway through and take the rest of the buffer's marks with it.
local function mark(buf, line, lines)
  if type(line) ~= 'number' then return end
  if line < 1 or line > vim.api.nvim_buf_line_count(buf) then return end
  vim.api.nvim_buf_set_extmark(buf, M.ns, line - 1, 0, { virt_lines = lines })
end

-- Virtual lines hang under the *end* line only, so a multi-line comment reads as
-- a comment on that one line. Tinting every covered line is what makes the range
-- visible as a range. The low priority is load-bearing: mini.diff paints changed
-- lines with its own line background, and that git signal must win where the two
-- overlap. Same gate as `mark`: lines outside the buffer draw nothing.
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

function M.render(buf, relpath, entries, threads)
  M.clear(buf)
  for _, e in ipairs(entries or {}) do
    if e.path == relpath then
      range_tint(buf, e.start_line, e.line, 'ReviewPendingRange')
      mark(buf, e.line, virt_lines('[pending] ', e.body, { 'ReviewPendingRange', 'ReviewPending' }))
    end
  end
  for _, t in ipairs(threads or {}) do
    if t.path == relpath and t.side ~= 'LEFT' then
      range_tint(buf, t.start_line, t.line, 'ReviewRemoteRange')
      mark(buf, t.line, virt_lines('@' .. t.author .. ': ', t.body, { 'ReviewRemoteRange', 'ReviewRemote' }))
    end
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
    add(e.path, e.line, '[pending] ' .. store.first_line(e.body))
  end
  for _, t in ipairs(threads or {}) do
    add(t.path, t.line, '@' .. t.author .. ': ' .. store.first_line(t.body))
  end
  vim.fn.setqflist({}, ' ', { title = 'PR review comments', items = items })
end

return M
