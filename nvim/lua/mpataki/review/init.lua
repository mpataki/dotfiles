-- Review comments from nvim: commands, keymaps, and glue between pr/store/
-- render/capture. Push and pull live in sync.lua (Task 7) but are registered
-- here so the command surface is in one place.
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local render = require('mpataki.review.render')
local capture = require('mpataki.review.capture')

local M = {}

local function notify_err(msg)
  vim.notify('review: ' .. msg, vim.log.levels.ERROR)
end

local function repo_context(root)
  local info, err = pr.info(root)
  if not info then return nil, err end
  if not info.number then return nil, 'no PR for this branch (gh pr view found none)' end
  return {
    root = root,
    info = info,
    file = store.path(info.common_dir, info.number),
    remote_file = store.remote_path(info.common_dir, info.number),
  }
end

-- A file buffer's review context; nil, err when it has no file, no repo, or no PR.
function M.context(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.bo[bufnr].buftype ~= '' then return nil, 'buffer has no file' end
  local root = pr.root(path)
  if not root then return nil, 'not in a git repo' end
  local relpath = pr.relpath(root, path)
  if not relpath then return nil, 'file outside repo' end
  local ctx, err = repo_context(root)
  if not ctx then return nil, err end
  ctx.relpath = relpath
  return ctx
end

-- The repo a gesture acts on when it needs no file: quickfix and the escape
-- hatch work from neo-tree, the quickfix window, or an empty buffer.
local function current_context()
  local root = pr.current_root()
  if not root then return nil, 'not in a git repo' end
  return repo_context(root)
end

function M.load_threads(ctx)
  if vim.fn.filereadable(ctx.remote_file) ~= 1 then return {} end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(ctx.remote_file), '\n'))
  if not ok or type(data) ~= 'table' then return {} end
  return data
end

local function render_buf(bufnr, ctx)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local doc = store.read(ctx.file)
  render.render(bufnr, ctx.relpath, doc.entries, M.load_threads(ctx))
end

function M.render_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local ctx, err = M.context(bufnr)
  if not ctx then return notify_err(err) end
  render_buf(bufnr, ctx)
end

function M.refresh()
  pr.clear_cache()
  M.render_current()
end

local function anchor_from_range(range)
  if not range or range.range == 0 then
    local line = vim.api.nvim_win_get_cursor(0)[1]
    return line, nil
  end
  local s, e = range.line1, range.line2
  if s == e then return s, nil end
  return e, s
end

-- Every line of a range must sit in a hunk, not just its ends: GitHub rejects
-- a range that bridges the gap between two hunks.
local function first_line_outside(ranges, line, start_line)
  for l = start_line or line, line do
    if not pr.in_ranges(ranges, l) then return l end
  end
  return nil
end

-- opts: command opts (range/line1/line2) or nil for a plain call.
function M.comment(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local ctx, err = M.context(bufnr)
  if not ctx then return notify_err(err) end

  local line, start_line = anchor_from_range(opts)
  local head = ctx.info.head or 'HEAD'
  local ranges, derr = pr.diff_ranges(ctx.root, ctx.info.base_sha, head, ctx.relpath)
  if not ranges then
    return notify_err(('no diff for %s against PR head %s: %s — fetch the PR branch?'):format(
      ctx.relpath, head:sub(1, 8), derr))
  end
  local outside = first_line_outside(ranges, line, start_line)
  if outside then
    return notify_err(('line %d is not in the PR diff; GitHub only anchors comments inside hunks (+3 context)'):format(outside))
  end

  local doc = store.read(ctx.file)
  local existing = store.find(doc, ctx.relpath, line, start_line)
  local title = store.key({ path = ctx.relpath, line = line, start_line = start_line })

  capture.open({
    title = title,
    body = existing and existing.body or '',
    on_save = function(body)
      -- Re-read: the file may have been hand-edited while the float was open.
      local fresh = store.read(ctx.file)
      store.upsert(fresh, { path = ctx.relpath, line = line, start_line = start_line, body = body })
      store.write(ctx.file, fresh)
      render_buf(bufnr, ctx)
    end,
  })
end

function M.quickfix()
  local ctx, err = current_context()
  if not ctx then return notify_err(err) end
  local doc = store.read(ctx.file)
  render.quickfix(ctx.root, doc.entries, M.load_threads(ctx))
  vim.cmd('copen')
end

function M.open_file()
  local ctx, err = current_context()
  if not ctx then return notify_err(err) end
  vim.fn.mkdir(vim.fn.fnamemodify(ctx.file, ':h'), 'p')
  vim.cmd('edit ' .. vim.fn.fnameescape(ctx.file))
end

-- Passive render on every window entry. Gated on the reviews dir existing so a
-- repo with no review files never pays for `gh pr view` on its first file open
-- (that call is a network round-trip that blocks the editor); `pr.root` and
-- `pr.common_dir` are local git calls.
local function on_buf_win_enter(ev)
  if vim.bo[ev.buf].buftype ~= '' then return end
  local root = pr.root(vim.api.nvim_buf_get_name(ev.buf))
  if not root then return end
  if vim.fn.isdirectory(pr.common_dir(root) .. '/reviews') == 0 then return end
  local ctx = M.context(ev.buf)
  if not ctx then return end
  if vim.fn.filereadable(ctx.file) ~= 1 and vim.fn.filereadable(ctx.remote_file) ~= 1 then return end
  render_buf(ev.buf, ctx)
end

function M.setup()
  local cmd = vim.api.nvim_create_user_command
  cmd('ReviewComment', M.comment, { range = true, desc = 'Review: comment at cursor/selection' })
  cmd('ReviewRender', M.render_current, { desc = 'Review: re-render comments in buffer' })
  cmd('ReviewRefresh', M.refresh, { desc = 'Review: drop cached PR identity and re-render' })
  cmd('ReviewQuickfix', M.quickfix, { desc = 'Review: comments → quickfix' })
  cmd('ReviewOpen', M.open_file, { desc = 'Review: open pending comments file' })
  cmd('ReviewPush', function(o) require('mpataki.review.sync').push(o.bang) end,
    { bang = true, desc = 'Review: push pending comments as a draft GitHub review' })
  cmd('ReviewPull', function() require('mpataki.review.sync').pull() end,
    { desc = 'Review: pull remote threads + my pending review' })

  vim.keymap.set('n', '<leader>gc', M.comment, { desc = 'Review comment at cursor' })
  -- ':' from visual mode supplies the '<,'> range; <Cmd> would not.
  vim.keymap.set('x', '<leader>gc', ':ReviewComment<CR>', { silent = true, desc = 'Review comment on selection' })
  vim.keymap.set('n', '<leader>gC', M.quickfix, { desc = 'Review comments → quickfix' })

  local group = vim.api.nvim_create_augroup('MpatakiReview', { clear = true })
  vim.api.nvim_create_autocmd('BufWinEnter', { group = group, callback = on_buf_win_enter })
end

return M
