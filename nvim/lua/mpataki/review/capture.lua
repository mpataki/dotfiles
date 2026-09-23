-- Anchored float for authoring one review comment. Owns nothing but the
-- window: the caller supplies the initial body and receives the final one.
-- `:w` works because the buffer is `acwrite` and BufWriteCmd intercepts it.
local M = {}

local HEIGHT = 6

local function close(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

-- Exact name only: bufnr(name) takes a file-pattern and falls back to a partial
-- match, so 'path:5' would find a live 'path:5-8' float and wipe that draft.
local function find_buf(name)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == name then return b end
  end
  return nil
end

-- A float the user tabbed away from is still open under this name: opening a
-- second one would raise E95 on nvim_buf_set_name. Focus it instead; a stale
-- buffer nobody displays is wiped so the name is free.
local function reuse_existing(name)
  local buf = find_buf(name)
  if not buf then return nil end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_set_current_win(win)
      return win, buf
    end
  end
  vim.api.nvim_buf_delete(buf, { force = true })
  return nil
end

-- Below the cursor unless that would push the float off the bottom, where nvim
-- would slide it back up over the very line being commented on. screenpos(),
-- not screenrow(): the latter is the *screen* cursor, which sits on the command
-- line right after a message and would flip every float above its line.
local function placement()
  local row = vim.fn.screenpos(0, vim.fn.line('.'), 1).row
  local rows_left = vim.o.lines - vim.o.cmdheight - row
  if rows_left >= HEIGHT + 2 then return { anchor = 'NW', row = 1 } end
  return { anchor = 'SW', row = 0 }
end

function M.open(opts)
  local name = 'review://' .. opts.title
  local win, buf = reuse_existing(name)
  if win then return win, buf end

  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'acwrite'
  -- 'hide', not 'wipe': `:q` on a modified buffer is E37 unless the buffer may
  -- be hidden. Marking it clean up front instead (QuitPre) breaks `:wqa`/`:xa`,
  -- which only write *changed* buffers. So it hides, and BufHidden wipes it.
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(buf, name)
  local lines = vim.split(opts.body or '', '\n', { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local place = placement()
  local width = math.min(80, math.max(40, vim.o.columns - 10))
  win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    anchor = place.anchor,
    row = place.row,
    col = 0,
    width = width,
    height = HEIGHT,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. opts.title .. ' ',
    title_pos = 'left',
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  -- on_save runs synchronously: `:wqa` writes, then quits before the event
  -- loop gets another tick, so a deferred save is a lost comment. Only the
  -- close is deferred — `:wq` runs the write, then quits *whatever window is
  -- current*, and with the float already gone that is the code window (or
  -- nvim itself when it was the last one).
  local function save()
    local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    -- on_save returning false means the comment did not land anywhere: leave
    -- the float open and the buffer modified, or :w would silently eat it.
    if opts.on_save(body) == false then return end
    vim.bo[buf].modified = false
    vim.cmd('stopinsert')
    vim.schedule(function() close(win) end)
  end

  local function cancel()
    vim.bo[buf].modified = false
    vim.cmd('stopinsert')
    close(win)
  end

  vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = save })
  vim.api.nvim_create_autocmd('BufHidden', {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
      end)
    end,
  })
  vim.keymap.set({ 'n', 'i' }, '<C-s>', save, { buffer = buf })
  vim.keymap.set('n', 'q', cancel, { buffer = buf })

  vim.api.nvim_win_set_cursor(win, { #lines, 0 })
  vim.cmd('startinsert!')
  return win, buf
end

return M
