return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
        -- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
    },
    config = function()
        require("neo-tree").setup({
            filesystem = {
                hijack_netrw_behavior = "open_current",
                follow_current_file = {
                    enabled = true,
                    leave_dirs_open = true,
                },
                filtered_items = {
                    always_show = {
                        ".github"
                    },
                }
            },
            window = {
                width = 50,
            },
            default_component_configs = {
                created = { enabled = false },
                last_modified = { enabled = false },
                file_size = { enabled = false },
                type = { enabled = false },
            }
        })

        vim.keymap.set('n', '<Leader>t', ':Neotree<CR>')
        -- vim.keymap.set('n', '<Leader>t', '<cmd>:Neotree position=current<CR>')
    end
}
