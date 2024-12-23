return {
    {
        'MeanderingProgrammer/render-markdown.nvim',
        dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
        ---@module 'render-markdown'
        ---@type render.md.UserConfig
        opts = {
            file_types = { "markdown", "Avante" },
            bullet = {
                enabled = true,
                icons = { '●', '○', '◆', '◇' },
                ordered_icons = function(level, index, value)
                    value = vim.trim(value)
                    local value_index = tonumber(value:sub(1, #value - 1))
                    return string.format('%d.', value_index > 1 and value_index or index)
                end,
                left_pad = 0,
                right_pad = 1,
                highlight = 'RenderMarkdownBullet',
            },
            checkbox = {
                enabled = true,
                position = 'inline',
                unchecked = {
                    icon = '󰄱',
                    highlight = 'RenderMarkdownUnchecked',
                    scope_highlight = nil,
                },
                checked = {
                    icon = '󰄲',
                    highlight = 'RenderMarkdownChecked',
                    scope_highlight = nil,
                },
                custom = {
                    todo = { raw = '[-]', rendered = '󰥔', highlight = 'RenderMarkdownTodo', scope_highlight = nil },
                    star = { raw = '[*]', rendered = '⭐︎', highlight = 'RenderMarkdownStar', scope_highlight = nil },
                    bang = { raw = '[!]', rendered = '❗', highlight = 'RenderMarkdownBang', scope_highlight = nil },
                    bangbang = { raw = '[!!]', rendered = '‼️', highlight = 'RenderMarkdownBangBang', scope_highlight = nil },
                    rightarrow = { raw = '[>]', rendered = '▶︎', highlight = 'RenderMarkdownRightArrow', scope_highlight = nil }
                },
            },
        },
        ft = { "markdown", "Avante" },
    }
}
