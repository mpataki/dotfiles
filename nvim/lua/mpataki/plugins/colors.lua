
-- colorschemes
-- { 'srcery-colors/srcery-vim', lazy=true, priority=1000 },
return {
    -- 'folke/tokyonight.nvim',
    -- 'kabbamine/yowish.vim',
    'catppuccin/nvim',
    lazy = false,
    priority = 1000,
    config = function()
        require("catppuccin").setup({
            flavor = 'mocha',
            transparent_background = true,
            term_colors = true,
            custom_highlights = function(colors)
                return {
                    DiffAdd = { bg = "#122a12" },
                    DiffChange = { bg = "#12202a" },
                    DiffDelete = { bg = "#2a1212" },
                    DiffText = { bg = "#1e2a12" },
                }
            end,
        })

        vim.cmd.colorscheme("catppuccin")

        -- require("tokyonight").setup({
        --     style = 'night',
        --     transparent = true,
        -- })
        --
        -- vim.cmd.colorscheme("tokyonight")

        -- vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
        -- vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#141414" })

        -- subtle dark float background for hover etc.
        vim.cmd("highlight NormalFloat guibg=#121218")
        vim.cmd("highlight FloatBorder guibg=NONE")
        vim.cmd("highlight FloatTitle guibg=NONE")

        -- vim.cmd([[
        -- highlight StatusLine guibg=LightBlue
        -- ]])
    end
}

-- { 'srcery-colors/srcery-vim', lazy=true, priority=1000 },
-- { 'embark-theme/vim', lazy=true, priority=1000 },

