return {
    {
        'nvim-telescope/telescope.nvim',
        tag = '0.1.4',
        dependencies = { 'nvim-lua/plenary.nvim' },
    },
    { 'nvim-telescope/telescope-ui-select.nvim' },
    { 'nvim-telescope/telescope-dap.nvim' },
    { 'nvim-treesitter/nvim-treesitter', cmd='TSUpdate' },
    { 'theprimeagen/harpoon' },
    { 'mbbill/undotree' },
    -- { 'tpope/vim-fugitive' }, -- git client
    { 'airblade/vim-gitgutter' },

    -- LSP-zero:
    {
        -- specifying registries here to allow for updating java-test. Try removing the registries in a few weeks.
        -- https://github.com/mason-org/mason-registry/pull/3348#issuecomment-1842510761
        'williamboman/mason.nvim',
        opts = {
            registries = {
                'github:nvim-java/mason-registry',
			    'github:mason-org/mason-registry',
            }
        }
    },
    { 'williamboman/mason-lspconfig.nvim' },
    { 'VonHeikemen/lsp-zero.nvim', branch = 'v3.x' },
    { 'neovim/nvim-lspconfig' },
    { 'L3MON4D3/LuaSnip' },

    { 'mfussenegger/nvim-jdtls' },
    { 'mfussenegger/nvim-dap' },
    { 'rcarriga/nvim-dap-ui' },
    { 'jay-babu/mason-nvim-dap.nvim' },

    {
        "nvim-neo-tree/neo-tree.nvim",
        branch = "v3.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-tree/nvim-web-devicons",
            "MunifTanjim/nui.nvim",
            -- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
        }
    },

    -- colorschemes
    -- { 'srcery-colors/srcery-vim', lazy=true, priority=1000 },
    { 'kabbamine/yowish.vim', lazy=true, priority=1000 },
    -- { 'srcery-colors/srcery-vim', lazy=true, priority=1000 },
    -- { 'embark-theme/vim', lazy=true, priority=1000 },
}
