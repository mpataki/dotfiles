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

lsp.configure('gopls', {
    capabilities = require('cmp_nvim_lsp').default_capabilities(),
    root_dir = require('lspconfig.util').root_pattern('go.work', 'go.mod', '.git'),
    settings = {
        gopls = {
            analyses = {
                unusedparams = true,
            },
            staticcheck = true,
            gofumpt = true,
            usePlaceholders = true,
            completeUnimported = true,
            expandWorkspaceToModule = true,
        },
    },
})

lsp.on_attach(function(client, bufnr)
    local mapper = function(mode, key, result)
        vim.api.nvim_buf_set_keymap(0, mode, key, result, {noremap=true, silent=true})
    end

	-- see :help lsp-zero-keybindings
	-- to learn the available actions
	-- lsp.default_keymaps({
 --        buffer = bufnr,
 --        remap = false
 --    })

    mapper('n', 'K',    '<cmd>lua vim.lsp.buf.hover()<CR>')
    mapper('n', 'gd',   '<cmd>lua vim.lsp.buf.definition()<CR>')
    mapper('n', 'gD',   '<cmd>lua vim.lsp.buf.declaration()<CR>')
    mapper('n', 'gi',   '<cmd>lua vim.lsp.buf.implementation()<CR>')
    mapper('n', 'go',   '<cmd>lua vim.lsp.buf.type_definition()<CR>')
    mapper('n', 'gr',   '<cmd>lua require("telescope.builtin").lsp_references()<CR>')
    mapper('n', 'gs',   '<cmd>lua vim.lsp.buf.signature_help()<CR>')
    mapper('n', 'gR',   '<cmd>lua vim.lsp.buf.rename()<CR>')
    mapper('n', 'ga',   '<cmd>lua vim.lsp.buf.code_action()<CR>')
    mapper('n', 'gl',   '<cmd>lua vim.diagnostic.open_float()<CR>')
    mapper('n', '[d',   '<cmd>lua vim.diagnostic.goto_prev()<CR>')
    mapper('n', ']d',   '<cmd>lua vim.diagnostic.goto_next()<CR>')
end)

require('mason').setup({})

require('mason-lspconfig').setup({
    ensure_installed = {
        'lua_ls',
        'rust_analyzer',
        'ts_ls',
        'eslint',
        'bashls',
        'yamlls',
        'gradle_ls',
        'marksman', -- markdown
        'gopls',
        -- 'clangd', -- Let's use the system clangd
        -- 'jdtls', -- I'll roll this one manually to get more control.. java..
    },
    handlers = {
        lsp.default_setup,
    },
})

require('mason-nvim-dap').setup({
    -- list of adapters https://github.com/jay-babu/mason-nvim-dap.nvim/blob/main/lua/mason-nvim-dap/mappings/source.lua 
    ensure_installed = {
        'javadbg',
        'javatest',
        'js-debug-adapter',
        'codelldb',
        'delve',
    },
})

lsp.setup()

