local lsp_zero = require('lsp-zero')

lsp_zero.on_attach(function(client, bufnr)
	local opts = { buffer = bufnr, remap = false }

	-- see :help lsp-zero-keybindings
	-- to learn the available actions
	lsp_zero.default_keymaps(opts)
end)

require('lspconfig').lua_ls.setup({})
require('lspconfig').rust_analyzer.setup({})
require('lspconfig').tsserver.setup({})
require('lspconfig').eslint.setup({})
require('lspconfig').java_language_server.setup({})
require('lspconfig').bashls.setup({})
require('lspconfig').yamlls.setup({})
