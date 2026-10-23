-- The agent side of a review: hand the whole draft to the Claude pane
-- (:ReviewSend, <leader>cr) and start over (:ReviewClear). The draft file is
-- the interface: the agent reads it, nothing is reformatted for it.
local review = require('mpataki.review')
local store = require('mpataki.review.store')
local sync = require('mpataki.review.sync')

local M = {}

local function fail(msg)
  vim.notify('review: ' .. msg, vim.log.levels.ERROR)
end

function M.message(file)
  return ('Review comments for this branch: %s\n'
    .. 'Each "## path:line" heading is a comment on that location (path:start-end = a range). '
    .. 'Address each one.'):format(file)
end

-- ctx, doc, or nil once the refusal is reported. An unwritten draft buffer
-- means the file on disk is not what you are looking at.
local function draft(command)
  local ctx = sync.repo_for(command)
  if not ctx then return nil end
  if sync.unsaved(ctx) then
    return fail(('%s has unwritten changes: write the comments file first (:w)'):format(ctx.file))
  end
  local doc = store.read(ctx.file)
  if #doc.entries == 0 then return fail(command .. ': no comments in ' .. ctx.file) end
  return ctx, doc
end

function M.send()
  local ctx, doc = draft(':ReviewSend')
  if not ctx then return end
  require('mpataki.ask').send(M.message(ctx.file), function(ok, err, row)
    if not ok then return fail('send failed: ' .. tostring(err)) end
    vim.notify(('review: sent %d comment(s) to claude %s'):format(#doc.entries,
      require('mpataki.ask.target').label(row)))
  end)
end

-- Archive, not delete: the comments are what you told the agent, and the
-- archive is the record of it.
function M.archive_path(file, stamp)
  return (file:gsub('%.md$', '')) .. '.' .. stamp .. '.md'
end

function M.clear()
  local ctx, doc = draft(':ReviewClear')
  if not ctx then return end
  if not sync.confirm(('Archive %d comment(s) and start an empty review?'):format(#doc.entries)) then
    return vim.notify('review: clear cancelled')
  end
  local dest = M.archive_path(ctx.file, os.date('%Y%m%d-%H%M%S'))
  local ok, err = vim.uv.fs_rename(ctx.file, dest)
  if not ok then return fail(('cannot archive %s: %s'):format(ctx.file, tostring(err))) end
  vim.cmd('checktime')
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local bctx = review.context(buf)
    if bctx and bctx.file == ctx.file then review.render_buf(buf, bctx) end
  end
  vim.notify('review: archived to ' .. dest)
end

return M
