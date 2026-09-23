-- Draws pending and remote comments as virtual lines under their anchor line
-- and fills the quickfix list. Pure presentation: no git, no gh, no file IO.
local M = {}

M.ns = vim.api.nvim_create_namespace('mpataki_review')

-- `default = true` is load-bearing, not politeness: ':colorscheme' runs
-- ':highlight clear', which wipes an explicit link but re-applies a default one.
-- Without it this module would need a ColorScheme autocmd to keep its colors
-- across a theme switch. Load order does not matter for the same reason.
vim.api.nvim_set_hl(0, 'ReviewPending', { default = true, link = 'DiagnosticVirtualTextWarn' })
vim.api.nvim_set_hl(0, 'ReviewRemote', { default = true, link = 'Comment' })

-- GitHub returns comment bodies with CRLF endings. Splitting on '\n' alone
-- leaves a trailing '\r', and nvim transliterates that into a literal '^M' at
-- the end of every rendered line.
local function body_lines(body)
  local text = ((body or ''):gsub('\r', ''))
  return vim.split(text, '\n', { plain = true })
end

local function virt_lines(prefix, body, hl)
  -- Display width, not #prefix: the prefix carries a multi-byte box-drawing
  -- glyph, so byte-length padding pushes continuation lines out of alignment.
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

function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
end

function M.render(buf, relpath, entries, threads)
  M.clear(buf)
  for _, e in ipairs(entries or {}) do
    if e.path == relpath then
      mark(buf, e.line, virt_lines('  ┃ [pending] ', e.body, 'ReviewPending'))
    end
  end
  for _, t in ipairs(threads or {}) do
    if t.path == relpath and t.side ~= 'LEFT' then
      mark(buf, t.line, virt_lines('  ┃ @' .. t.author .. ': ', t.body, 'ReviewRemote'))
    end
  end
end

local function first_line(s)
  return body_lines(s)[1]
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
    add(e.path, e.line, '[pending] ' .. first_line(e.body))
  end
  for _, t in ipairs(threads or {}) do
    add(t.path, t.line, '@' .. t.author .. ': ' .. first_line(t.body))
  end
  vim.fn.setqflist({}, ' ', { title = 'PR review comments', items = items })
end

return M
