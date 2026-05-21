-- Reload buffers changed externally (AI agents, git, other editors)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
    command = "silent! checktime",
})

-- set external formatter to the google java formatter, as installed by mason, for java files
vim.api.nvim_create_autocmd("FileType", {
    pattern = "java",
    callback = function()
        vim.bo.formatprg = os.getenv('HOME') .. '/.local/share/nvim/mason/bin/google-java-format -'
    end
})

-- Tree-sitter syntax error highlighting
local ts_error_ns = vim.api.nvim_create_namespace('mpataki_ts_syntax_errors')
vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
    pattern = {"*.cpp", "*.c", "*.h", "*.hpp", "*.cc", "*.cxx"},
    callback = function()
        local ts_utils = require('nvim-treesitter.ts_utils')
        local parsers = require('nvim-treesitter.parsers')

        -- Create a function to highlight syntax errors
        local function highlight_syntax_errors()
            local buf = vim.api.nvim_get_current_buf()
            local filetype = vim.bo[buf].filetype

            if not parsers.has_parser(filetype) then
                return
            end

            -- Clear existing error highlights
            vim.api.nvim_buf_clear_namespace(buf, ts_error_ns, 0, -1)

            -- Get tree-sitter tree
            local ok, tree = pcall(vim.treesitter.get_parser, buf, filetype)
            if not ok or not tree then
                return
            end

            -- Check for ERROR nodes
            local query = vim.treesitter.query.parse(filetype, '(ERROR) @error')

            for _, node in query:iter_captures(tree:parse()[1]:root(), buf) do
                local start_row, start_col, end_row, end_col = node:range()

                -- Highlight the error
                vim.hl.range(buf, ts_error_ns, 'ErrorMsg', { start_row, start_col }, { end_row, end_col })
            end
        end
        
        -- Run on buffer changes
        vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
            buffer = 0,
            callback = highlight_syntax_errors,
        })
        
        -- Run immediately
        vim.defer_fn(highlight_syntax_errors, 100)
    end
})
