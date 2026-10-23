-- What a message to the agent says. Pure: strings in, strings out.
local M = {}

function M.ref(path, start_line, end_line)
  if end_line and end_line ~= start_line then
    return ('%s:%d-%d'):format(path, start_line, end_line)
  end
  return ('%s:%d'):format(path, start_line)
end

-- Trimmed, CR-free; '' means there is nothing to send.
function M.body(text)
  return vim.trim((text or ''):gsub('\r', ''))
end

function M.message(ref, body)
  return ref .. '\n\n' .. body
end

-- The agent resolves paths against its own cwd, which need not be nvim's (one
-- session runs Claude in ~/go/src/…/b5 and nvim in ~/code/b5). Repo-relative
-- only when the pane sits at this repo's root; absolute otherwise.
function M.path_for(abs_path, repo_root, pane_cwd)
  local function real(p) return p and (vim.uv.fs_realpath(p) or p) end
  local abs, root, cwd = real(abs_path), real(repo_root), real(pane_cwd)
  if root and cwd == root and abs:sub(1, #root + 1) == root .. '/' then
    return abs:sub(#root + 2)
  end
  return abs
end

return M
