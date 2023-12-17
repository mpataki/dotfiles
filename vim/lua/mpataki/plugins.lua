return {
    {
        'nvim-telescope/telescope.nvim',
        tag = '0.1.4',
        dependencies = { 'nvim-lua/plenary.nvim' },
    },
    {'nvim-telescope/telescope-ui-select.nvim'},
    { "nvim-treesitter/nvim-treesitter", cmd='TSUpdate' },
    { "theprimeagen/harpoon" },
    { "mbbill/undotree" },
    -- { "tpope/vim-fugitive" }, -- git client
    { "airblade/vim-gitgutter" },
    { 'numToStr/Comment.nvim' },

    -- LSP-zero:
    {'williamboman/mason.nvim'},
    {'williamboman/mason-lspconfig.nvim'},
    {'VonHeikemen/lsp-zero.nvim', branch = 'v3.x'},
    {'neovim/nvim-lspconfig'},
    {'hrsh7th/cmp-nvim-lsp'},
    {'hrsh7th/nvim-cmp'},
    {'L3MON4D3/LuaSnip'},

    -- java lsp/debugging
    {
        'mfussenegger/nvim-jdtls',
        dependencies={
            {'microsoft/java-debug'},
            {'microsoft/vscode-java-test'},
        }
    },
    {'mfussenegger/nvim-dap'},
    {'rcarriga/nvim-dap-ui'},
    {'jay-babu/mason-nvim-dap.nvim'},

    -- colorschemes
    -- { "srcery-colors/srcery-vim", lazy=true, priority=1000 },
    { "kabbamine/yowish.vim", lazy=true, priority=1000 },
    -- { "srcery-colors/srcery-vim", lazy=true, priority=1000 },
    -- { "embark-theme/vim", lazy=true, priority=1000 },
}
