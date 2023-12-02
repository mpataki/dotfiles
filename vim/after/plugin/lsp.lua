local lsp = require('lsp-zero')

-- Fix Undefined global 'vim' in neovim lua
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
	-- see :help lsp-zero-keybindings
	-- to learn the available actions
	lsp.default_keymaps({
        buffer = bufnr,
        remap = false
    })

    -- more lsp remaps
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action)
end)

require('mason').setup({})
require('mason-lspconfig').setup({
    ensure_installed = {
        'lua_ls',
        'rust_analyzer',
        'tsserver',
        'eslint',
        'bashls',
        'yamlls',
        'gradle_ls',
        -- 'bufls',
    },
    handlers = {
        lsp.default_setup,
    },
})

lsp.setup()

