-- Listen on a deterministic socket per project so external tools (e.g.
-- nvim-goto, claude code) can drive this nvim. Path matches what nvim-goto
-- computes: /tmp/nvim-sockets/<sha256(project_root):16>.pipe.
-- project_root = git toplevel of cwd, falling back to cwd itself.

local function project_root()
    local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
    local root
    if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
        root = out[1]
    else
        root = vim.fn.getcwd()
    end
    -- Resolve symlinks (e.g. /tmp -> /private/tmp on macOS) so the hash
    -- matches what nvim-goto computes from the shell side via `pwd -P`.
    return vim.fn.resolve(root)
end

-- Headless instances (probes, scripts) never claim the project socket: they
-- would take it from the editor the user is actually driving.
if vim.tbl_contains(vim.v.argv, "--headless") then return end

local socket_dir = "/tmp/nvim-sockets"
vim.fn.mkdir(socket_dir, "p")

local hash = vim.fn.sha256(project_root()):sub(1, 16)
local socket_path = socket_dir .. "/" .. hash .. ".pipe"

-- One nvim per project is the working assumption. A socket left by a crashed
-- nvim is removed and reclaimed; one that still answers belongs to a live nvim
-- and is left alone (this instance just goes without).
local ok, addr = pcall(vim.fn.serverstart, socket_path)
if not ok or addr == "" then
    local live, chan = pcall(vim.fn.sockconnect, "pipe", socket_path, { rpc = true })
    if live and chan > 0 then
        vim.fn.chanclose(chan)
        return
    end
    pcall(vim.fn.delete, socket_path)
    pcall(vim.fn.serverstart, socket_path)
end
