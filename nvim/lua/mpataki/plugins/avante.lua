local func = require "vim.func"
return {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false, -- set this if you want to always pull the latest change
    opts = {
        { -- mostly defaults, see https://github.com/yetone/avante.nvim?tab=readme-ov-file#default-setup-configuration
            ---@alias Provider "claude" | "openai" | "azure" | "gemini" | "cohere" | "copilot" | string
            provider = "claude", -- Recommend using Claude
            auto_suggestions_provider = "copilot", -- Since auto-suggestions are a high-frequency operation and therefore expensive, it is recommended to specify an inexpensive provider or even a free provider: copilot
            claude = {
                endpoint = "https://api.anthropic.com",
                model = "claude-3-5-sonnet-20241022",
                temperature = 0,
                max_tokens = 4096,
            },
            behaviour = {
                auto_suggestions = false, -- Experimental stage
                auto_set_highlight_group = true,
                auto_set_keymaps = true,
                auto_apply_diff_after_generation = false,
                support_paste_from_clipboard = false,
            },
            mappings = {
                --- @class AvanteConflictMappings
                diff = {
                    ours = "co",
                    theirs = "ct",
                    all_theirs = "ca",
                    both = "cb",
                    cursor = "cc",
                    next = "]x",
                    prev = "[x",
                },
                suggestion = {
                    accept = "<M-l>",
                    next = "<M-]>",
                    prev = "<M-[>",
                    dismiss = "<C-]>",
                },
                jump = {
                    next = "]]",
                    prev = "[[",
                },
                submit = {
                    normal = "<CR>",
                    insert = "<C-s>",
                },
                sidebar = {
                    switch_windows = "<Tab>",
                    reverse_switch_windows = "<S-Tab>",
                },
            },
            hints = { enabled = true },
            windows = {
                ---@type "right" | "left" | "top" | "bottom"
                position = "right", -- the position of the sidebar
                wrap = true, -- similar to vim.o.wrap
                width = 30, -- default % based on available width
                sidebar_header = {
                    align = "center", -- left, center, right for title
                    rounded = true,
                },
            },
            highlights = {
                ---@type AvanteConflictHighlights
                diff = {
                    current = "DiffText",
                    incoming = "DiffAdd",
                },
            },
            --- @class AvanteConflictUserConfig
            diff = {
                autojump = true,
                ---@type string | fun(): any
                list_opener = "copen",
            },
        },
    },
    -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
    build = "make",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
        "stevearc/dressing.nvim",
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        --- The below dependencies are optional,
        "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
        -- "zbirenbaum/copilot.lua", -- for providers='copilot'
        {
            -- support for image pasting
            "HakonHarnes/img-clip.nvim",
            event = "VeryLazy",
            opts = {
                -- recommended settings
                default = {
                    embed_image_as_base64 = false,
                    prompt_for_file_name = false,
                    drag_and_drop = {
                        insert_mode = true,
                    },
                    -- required for Windows users
                    -- use_absolute_path = true,
                },
            },
        },
    },
    init = function ()
        -- views can only be fully collapsed with the global statusline
        vim.opt.laststatus = 3

        require('avante_lib').load();

        -- Avante-specific conflict highlights
        vim.api.nvim_set_hl(0, 'AvanteConflictCurrent', { bg = '#1f3a1f', bold = true })      -- Current changes (green)
        vim.api.nvim_set_hl(0, 'AvanteConflictIncoming', { bg = '#3a1f1f', bold = true })     -- Incoming changes (red)
        vim.api.nvim_set_hl(0, 'AvanteConflictAncestor', { bg = '#3a1f3a', bold = true })     -- Base version (purple)

        -- Labels for conflict sections (slightly darker versions)
        vim.api.nvim_set_hl(0, 'AvanteConflictCurrentLabel', { bg = '#2d4a2d', bold = true })  -- Darker green
        vim.api.nvim_set_hl(0, 'AvanteConflictIncomingLabel', { bg = '#4a2d2d', bold = true }) -- Darker red
        vim.api.nvim_set_hl(0, 'AvanteConflictAncestorLabel', { bg = '#4a2d4a', bold = true }) -- Darker purple
    end
}
