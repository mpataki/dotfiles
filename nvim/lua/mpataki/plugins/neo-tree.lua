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

        -- vim.keymap.set('n', '<Leader>t', '<cmd>:Neotree position=current<CR>')
        vim.keymap.set('n', '<Leader>ls', ':Neotree<CR>', { desc = 'Neotree' })

        local pr_tree_active = false
        vim.keymap.set('n', '<leader>gt', function()
            vim.cmd('Neotree git_base=HEAD')
            if pr_tree_active then
                vim.cmd('DiffReset')
                pr_tree_active = false
            end
        end, { desc = 'Neotree (HEAD)' })
        vim.keymap.set('n', '<leader>gT', function()
            local base_branch
            local base = vim.fn.system("git merge-base HEAD main 2>/dev/null"):gsub("%s+", "")
            if base ~= "" then
                base_branch = 'main'
            else
                base = vim.fn.system("git merge-base HEAD master 2>/dev/null"):gsub("%s+", "")
                base_branch = 'master'
            end
            if base == "" then
                vim.notify("Could not find merge base", vim.log.levels.ERROR)
                return
            end
            vim.cmd('Neotree git_base=' .. base)
            print('PR diff vs ' .. base_branch)
            pr_tree_active = true
        end, { desc = 'Neotree (PR base)' })
    end
}
