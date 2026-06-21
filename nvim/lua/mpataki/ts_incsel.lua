-- Treesitter incremental selection.
--
-- The nvim-treesitter `main` branch dropped the built-in incremental_selection
-- module, so this reimplements the four operations against Neovim's core
-- treesitter API. State is a per-window stack of nodes; init resets it, and
-- expand/shrink walk up/down that stack. Nodes are only held for the duration
-- of a selection (no edits happen meanwhile), so staleness is not a concern.

local M = {}

-- window id -> list of TSNode (innermost first, current selection is the last)
local stacks = {}

-- Drive Visual mode to cover a node's range. node:range() is 0-indexed with an
-- exclusive end column; the cursor needs an inclusive 0-indexed column. Setting
-- the '<'/'>' marks does not move a live selection, so when already in Visual
-- mode we drop out first and rebuild it with an anchor + cursor move.
local function visual_select(node)
    local srow, scol, erow, ecol = node:range()
    if ecol > 0 then
        ecol = ecol - 1
    else
        -- Range ends at column 0 of erow: it really covers through the prior line.
        erow = erow - 1
        ecol = math.max(vim.fn.col({ erow + 1, '$' }) - 2, 0)
    end
    local endline = vim.api.nvim_buf_get_lines(0, erow, erow + 1, false)[1] or ''
    ecol = math.min(ecol, math.max(#endline - 1, 0))

    local mode = vim.api.nvim_get_mode().mode
    if mode:find('[vV\22sS\19]') then
        vim.cmd('normal! \27') -- <Esc>: a fresh selection must start from normal mode
    end
    vim.api.nvim_win_set_cursor(0, { srow + 1, scol })
    vim.cmd('normal! v')
    vim.api.nvim_win_set_cursor(0, { erow + 1, ecol })
end

local function range_of(node)
    return { node:range() }
end

local function same_range(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

function M.init()
    local ok, parser = pcall(vim.treesitter.get_parser)
    if not ok or not parser then
        return
    end
    -- get_node only sees already-parsed regions; force the cursor row so this
    -- works even where the highlighter has not parsed yet (large files, etc.).
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    parser:parse({ row, row })
    local node = vim.treesitter.get_node()
    if not node then
        return
    end
    stacks[vim.api.nvim_get_current_win()] = { node }
    visual_select(node)
end

-- Expand to the smallest ancestor strictly larger than the current node.
function M.node_incremental()
    local win = vim.api.nvim_get_current_win()
    local stack = stacks[win]
    if not stack or #stack == 0 then
        return M.init()
    end
    local node = stack[#stack]
    local parent = node:parent()
    while parent and same_range(range_of(parent), range_of(node)) do
        parent = parent:parent()
    end
    if not parent then
        return visual_select(node)
    end
    table.insert(stack, parent)
    visual_select(parent)
end

-- Shrink back to the previously selected node.
function M.node_decremental()
    local win = vim.api.nvim_get_current_win()
    local stack = stacks[win]
    if not stack or #stack == 0 then
        return
    end
    if #stack > 1 then
        table.remove(stack)
    end
    visual_select(stack[#stack])
end

-- Expand to the nearest ancestor that spans more lines than the current node,
-- i.e. the enclosing multi-line scope.
function M.scope_incremental()
    local win = vim.api.nvim_get_current_win()
    local stack = stacks[win]
    if not stack or #stack == 0 then
        return M.init()
    end
    -- Effective last row, treating an exclusive column-0 end as the prior line.
    local function span(node)
        local sr, _, er, ec = node:range()
        if ec == 0 and er > sr then
            er = er - 1
        end
        return sr, er
    end
    local node = stack[#stack]
    local sr, er = span(node)
    local parent = node:parent()
    while parent do
        local psr, per = span(parent)
        if psr < sr or per > er then
            break
        end
        parent = parent:parent()
    end
    if not parent then
        return visual_select(node)
    end
    table.insert(stack, parent)
    visual_select(parent)
end

return M
