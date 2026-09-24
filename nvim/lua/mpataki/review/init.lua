-- PR review comments from nvim: draft inline comments on the PR's changed
-- lines, see everyone's threads as virtual text, push a pending GitHub review.
-- Commands, keymaps and glue between pr/store/render/capture; push and pull
-- live in sync.lua but register here so the command surface is in one place.
--
-- Usage: `gh pr checkout N` (or a worktree on the PR branch), open nvim there.
--   <leader>gS      pick a file changed in the PR
--   <leader>go      toggle the inline diff overlay (against the PR base)
--   <leader>gc      comment at the cursor or on the visual range; `:w` saves,
--                   `q` cancels, an empty body deletes the comment
--   <leader>gC      every comment, mine and remote, into the quickfix list
--   ]q / [q         walk that quickfix list (Neovim defaults)
--   :ReviewPull     fetch remote threads + my pending review, then re-render
--   :ReviewPush[!]  create/replace my pending review on GitHub; `!` skips the
--                   clobber guard (push over a pending review that has drifted)
--   <leader>gP      open the PR in the browser (:ReviewBrowse)
--   :ReviewOpen     edit the draft file directly (escape hatch)
--   :ReviewRender   re-render comments in this buffer
--   :ReviewRefresh  drop the cached PR identity and re-render — after a rebase,
--                   or when the PR is opened mid-session
--
-- Drafts live outside the worktree, in <git-common-dir>/reviews/<N>.md.
--
-- The review is meant to be finished in the browser, and two steps only happen
-- there: retiring a pending review (emptying the draft and pushing is refused,
-- so delete the review in the browser) and submitting the verdict.
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
  -- gh failing (unauthenticated, offline, rate-limited) is not the same as this
  -- branch having no PR, and the fix is different for each.
  if not info.number then
    if info.pr_err then return nil, 'no PR for this branch: ' .. info.pr_err end
    return nil, 'no PR for this branch (gh pr view found none)'
  end
  return {
    root = root,
    info = info,
    file = store.path(info.common_dir, info.number),
    remote_file = store.remote_path(info.common_dir, info.number),
  }
end

-- A file buffer's review context; nil, err when it has no file, no repo, or no
-- PR. `root` is optional: a caller that already resolved it (the BufWinEnter
-- path) passes it rather than paying for a second `git rev-parse` per entry.
function M.context(bufnr, root)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.bo[bufnr].buftype ~= '' then return nil, 'buffer has no file' end
  root = root or pr.root(path)
  if not root then return nil, 'not in a git repo' end
  local relpath = pr.relpath(root, path)
  if not relpath then return nil, 'file outside repo' end
  local ctx, err = repo_context(root)
  if not ctx then return nil, err end
  ctx.relpath = relpath
  return ctx
end

-- The repo a gesture acts on when it needs no file: quickfix, the escape hatch
-- and push/pull work from neo-tree, the quickfix window, an empty buffer, or
-- the comments file itself (which lives under .git, where `git rev-parse
-- --show-toplevel` refuses to answer, so the buffer's own path resolves to no
-- repo and only the cwd fallback finds one). No relpath: there is no file here.
function M.current_context()
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

-- The whole render sequence for one buffer: current draft, current remote
-- threads, redraw. Exported because sync.rerender runs it per window after a
-- pull, and drifting copies of it would draw two different pictures.
function M.render_buf(bufnr, ctx)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local doc = store.read(ctx.file)
  render.render(bufnr, ctx.relpath, doc.entries, M.load_threads(ctx))
end

function M.render_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local ctx, err = M.context(bufnr)
  if not ctx then return notify_err(err) end
  M.render_buf(bufnr, ctx)
end

function M.refresh()
  pr.clear_cache()
  M.render_current()
end

-- nil when the gesture carried no range: normal mode resolves its own anchor
-- against the comments already on the file (see M.comment).
local function anchor_from_range(range)
  if not range or range.range == 0 then return nil, nil end
  local s, e = range.line1, range.line2
  if s == e then return e, nil end
  return e, s
end

-- opts: command opts (range/line1/line2) or nil for a plain call.
function M.comment(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local ctx, err = M.context(bufnr)
  if not ctx then return notify_err(err) end

  local doc = store.read(ctx.file)
  local line, start_line = anchor_from_range(opts)
  -- Normal mode has only the cursor line to go on, and keying on it alone made a
  -- range comment reachable only by re-selecting its exact range — every other
  -- attempt started a second comment on one of its lines. Reopen the range that
  -- covers the cursor instead. Visual mode is untouched: the selection *is* the
  -- anchor, so it creates or replaces exactly that key.
  if not line then
    line = vim.api.nvim_win_get_cursor(0)[1]
    local covering = store.covering(doc, ctx.relpath, line)
    if covering then line, start_line = covering.line, covering.start_line end
  end
  local head = ctx.info.head or 'HEAD'
  local ranges, derr = pr.diff_ranges(ctx.root, ctx.info.base_sha, head, ctx.relpath)
  if not ranges then
    return notify_err(pr.no_diff_message(ctx.relpath, head, derr))
  end
  local outside = pr.first_line_outside(ranges, start_line, line)
  if outside then
    return notify_err(('line %d is not in the PR diff; GitHub only anchors comments inside hunks (+3 context)'):format(outside))
  end

  local existing = store.find(doc, ctx.relpath, line, start_line)
  local title = store.key({ path = ctx.relpath, line = line, start_line = start_line })

  capture.open({
    title = title,
    body = existing and existing.body or '',
    -- false keeps the float open with the draft still in it: closing on a
    -- failed write would throw away the comment the user just typed.
    on_save = function(body)
      -- Re-read: the file may have been hand-edited while the float was open.
      local fresh = store.read(ctx.file)
      store.upsert(fresh, { path = ctx.relpath, line = line, start_line = start_line, body = body })
      local ok, werr = store.write(ctx.file, fresh)
      if not ok then
        notify_err(werr)
        return false
      end
      M.render_buf(bufnr, ctx)
      return true
    end,
  })
end

function M.quickfix()
  local ctx, err = M.current_context()
  if not ctx then return notify_err(err) end
  local doc = store.read(ctx.file)
  render.quickfix(ctx.root, doc.entries, M.load_threads(ctx))
  vim.cmd('copen')
end

function M.open_file()
  local ctx, err = M.current_context()
  if not ctx then return notify_err(err) end
  vim.fn.mkdir(vim.fn.fnamemodify(ctx.file, ':h'), 'p')
  vim.cmd('edit ' .. vim.fn.fnameescape(ctx.file))
end

-- The review is finished in the browser (submit the verdict, retire a pending
-- review), so getting there is a gesture of its own rather than a copy out of
-- the push notification. current_context, like push: the buffer in front of you
-- when you reach for it is as likely to be the comments file as a source file.
function M.browse()
  local ctx, err = M.current_context()
  if not ctx then return notify_err(err) end
  local url = ctx.info.url
  if not url or url == '' then
    return notify_err(('no PR url for #%s; :ReviewRefresh to re-resolve it'):format(tostring(ctx.info.number)))
  end
  vim.ui.open(url)
end

-- Passive render on every window entry. Gated on the reviews dir existing so a
-- repo with no review files never pays for `gh pr view` on its first file open
-- (that call is a network round-trip that blocks the editor). What is left is
-- one `git rev-parse` per entry: common_dir is memoized per root, and context
-- is handed the root resolved here instead of resolving it a second time.
local function on_buf_win_enter(ev)
  if vim.bo[ev.buf].buftype ~= '' then return end
  local root = pr.root(vim.api.nvim_buf_get_name(ev.buf))
  if not root then return end
  if vim.fn.isdirectory(pr.common_dir(root) .. '/reviews') == 0 then return end
  local ctx = M.context(ev.buf, root)
  if not ctx then return end
  if vim.fn.filereadable(ctx.file) ~= 1 and vim.fn.filereadable(ctx.remote_file) ~= 1 then return end
  M.render_buf(ev.buf, ctx)
end

function M.setup()
  local cmd = vim.api.nvim_create_user_command
  cmd('ReviewComment', M.comment, { range = true, desc = 'Review: comment at cursor/selection' })
  cmd('ReviewRender', M.render_current, { desc = 'Review: re-render comments in buffer' })
  cmd('ReviewRefresh', M.refresh, { desc = 'Review: drop cached PR identity and re-render' })
  cmd('ReviewQuickfix', M.quickfix, { desc = 'Review: comments → quickfix' })
  cmd('ReviewOpen', M.open_file, { desc = 'Review: open pending comments file' })
  cmd('ReviewBrowse', M.browse, { desc = 'Review: open the PR in the browser' })
  cmd('ReviewPush', function(o) require('mpataki.review.sync').push(o.bang) end,
    { bang = true, desc = 'Review: push pending comments as a draft GitHub review' })
  cmd('ReviewPull', function() require('mpataki.review.sync').pull() end,
    { desc = 'Review: pull remote threads + my pending review' })

  vim.keymap.set('n', '<leader>gc', M.comment, { desc = 'Review comment at cursor' })
  -- ':' from visual mode supplies the '<,'> range; <Cmd> would not.
  vim.keymap.set('x', '<leader>gc', ':ReviewComment<CR>', { silent = true, desc = 'Review comment on selection' })
  vim.keymap.set('n', '<leader>gC', M.quickfix, { desc = 'Review comments → quickfix' })
  vim.keymap.set('n', '<leader>gP', M.browse, { desc = 'Open PR in browser' })

  local group = vim.api.nvim_create_augroup('MpatakiReview', { clear = true })
  vim.api.nvim_create_autocmd('BufWinEnter', { group = group, callback = on_buf_win_enter })
end

return M
