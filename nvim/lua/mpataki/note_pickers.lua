-- Project-scoped Obsidian note pickers (telescope-backed).
--
-- Scopes find/grep to the current repo's notes folder under the vault's
-- 01-projects/. Whole-vault search stays on obsidian.nvim's own bindings
-- (<leader>os content grep, <leader>ot tags, :Obsidian quick_switch).
local M = {}

local HOME = vim.fn.expand("~")
local VAULT = HOME .. "/obsidian-notes-vault"
local PROJECTS = VAULT .. "/01-projects"

-- Resolve the notes folder for the current buffer's repo.
-- Precedence: the nearest `.obsidian-project` file at or above the repo root
-- (first line = folder name under 01-projects/), else the git-toplevel
-- basename. Returns the absolute dir when it exists, else nil plus the name we
-- looked for.
--
-- The search continues past the repo root (stopping at $HOME) so one file can
-- cover a submodule from its superproject (a buffer under dotfiles/agent-config
-- roots at the submodule) and a container layout from the container dir
-- (~/code/<repo>/<worktree>, where the basename is a branch name).
local function project_notes_dir()
  local root = vim.fs.root(0, ".git") or vim.fn.getcwd()

  local name
  local override = vim.fs.find(".obsidian-project", {
    upward = true,
    type = "file",
    path = root,
    stop = HOME,
  })[1]
  if override then
    local first = vim.fn.readfile(override, "", 1)[1]
    if first then
      name = vim.trim(first)
    end
  end
  if not name or name == "" then
    name = vim.fs.basename(root)
  end

  local dir = PROJECTS .. "/" .. name
  if vim.fn.isdirectory(dir) == 1 then
    return dir, name
  end
  return nil, name
end

function M.find_project_notes()
  local builtin = require("telescope.builtin")
  local dir, name = project_notes_dir()
  if dir then
    builtin.find_files({ prompt_title = "Project notes: " .. name, cwd = dir })
  else
    vim.notify("No project notes for '" .. name .. "' — whole-vault find", vim.log.levels.WARN)
    builtin.find_files({ prompt_title = "Vault notes", cwd = VAULT })
  end
end

function M.grep_project_notes()
  local builtin = require("telescope.builtin")
  local dir, name = project_notes_dir()
  if dir then
    builtin.live_grep({ prompt_title = "Grep project notes: " .. name, cwd = dir })
  else
    vim.notify("No project notes for '" .. name .. "' — whole-vault grep", vim.log.levels.WARN)
    builtin.live_grep({ prompt_title = "Grep vault", cwd = VAULT })
  end
end

return M
