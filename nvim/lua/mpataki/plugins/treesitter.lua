return {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',
    lazy = false,
    build = ':TSUpdate',
    config = function()
        require('nvim-treesitter.configs').setup {
            ensure_installed = {
                'javascript',
                'typescript',
                'tsx',
                'java',
                'groovy',
                'python',
                'c',
                'lua',
                'vim',
                'vimdoc',
                'query',
                'go',
                'gomod',
                'rust',
                'proto',
                'terraform',
                'dockerfile',
                'xml',
                'cpp',
                'markdown',
                'markdown_inline',
                'sql',
                'ruby',
            },

            sync_install = false,
            auto_install = false,

            highlight = {
                enable = true,
                additional_vim_regex_highlighting = false,
            },

            incremental_selection = {
                enable = true,
                keymaps = {
                    init_selection = "<leader>ss",
                    node_incremental = "<leader>si",
                    scope_incremental = "<leader>sc",
                    node_decremental = "<leader>sd",
                },
            },

            indent = {
                enable = true,
                disable = { "python" },
            },
        }
    end
}
