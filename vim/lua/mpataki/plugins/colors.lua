
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

        -- disable the background in floating windows
        -- vim.cmd("highlight NormalFloat guibg=NONE")

        -- vim.cmd([[
        -- highlight StatusLine guibg=LightBlue
        -- ]])
    end
}

-- { 'srcery-colors/srcery-vim', lazy=true, priority=1000 },
-- { 'embark-theme/vim', lazy=true, priority=1000 },

