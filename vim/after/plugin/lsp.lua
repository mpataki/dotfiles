local lsp = require('lsp-zero')

-- Fix Undefined global 'vim'
lsp.configure('lua_ls', {
    settings = {
        Lua = {
            diagnostics = {
                globals = { 'vim' }
            }
        }
    }
})

lsp.on_attach(function(client, bufnr)
	local opts = { buffer = bufnr, remap = false }

	-- see :help lsp-zero-keybindings
	-- to learn the available actions
	lsp.default_keymaps(opts)
end)


require('mason').setup({})
require('mason-lspconfig').setup({
	-- Replace the language servers listed here 
	-- with the ones you want to install
	ensure_installed = {
		'lua_ls',
		'rust_analyzer',
		'tsserver',
		'eslint',
		-- 'java_language_server',
		'bashls',
		'yamlls',
	},
	handlers = {
		lsp.default_setup,
	},
})

lsp.setup()
