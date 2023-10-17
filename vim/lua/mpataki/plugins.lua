return {
	{
		'nvim-telescope/telescope.nvim',
		tag = '0.1.4',
		dependencies = { 'nvim-lua/plenary.nvim' },
	},
	-- { "srcery-colors/srcery-vim", lazy=true, priority=1000 },
	{ "kabbamine/yowish.vim", lazy=true, priority=1000 },
	{ "nvim-treesitter/nvim-treesitter", cmd='TSUpdate' },
	{ "theprimeagen/harpoon" },
	{ "mbbill/undotree" },
	{ "tpope/vim-fugitive" },
    { "airblade/vim-gitgutter" },

	-- LSP-zero:
	{'williamboman/mason.nvim'},
	{'williamboman/mason-lspconfig.nvim'},
	{'VonHeikemen/lsp-zero.nvim', branch = 'v3.x'},
	{'neovim/nvim-lspconfig'},
	{'hrsh7th/cmp-nvim-lsp'},
	{'hrsh7th/nvim-cmp'},
	{'L3MON4D3/LuaSnip'},
}
