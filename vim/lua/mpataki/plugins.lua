return {
	{ 
		'nvim-telescope/telescope.nvim', 
		tag = '0.1.4',
		dependencies = { 'nvim-lua/plenary.nvim' },
	},
	{ "srcery-colors/srcery-vim", lazy=true, priority=1000 },
	{ "nvim-treesitter/nvim-treesitter", cmd='TSUpdate' },
	{ "theprimeagen/harpoon" },
	{ "mbbill/undotree" },
	{ "tpope/vim-fugitive" },
}
