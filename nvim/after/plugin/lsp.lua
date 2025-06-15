local lspconfig = require('lspconfig')
local mason = require('mason')
local mason_lspconfig = require('mason-lspconfig')

-- Setup Mason first
mason.setup({})

-- LSP capabilities from cmp
local capabilities = require('cmp_nvim_lsp').default_capabilities()

-- Common LSP keybinding setup function
local function setup_lsp_keybindings(bufnr)
    -- Use the modern vim.keymap.set API with buffer option
    local opts = { noremap = true, silent = true, buffer = bufnr }
    
    vim.keymap.set('n', 'K',    vim.lsp.buf.hover, opts)
    vim.keymap.set('n', 'gd',   vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'gD',   vim.lsp.buf.declaration, opts)
    vim.keymap.set('n', 'gi',   vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', 'go',   vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', 'gr',   function() require('telescope.builtin').lsp_references() end, opts)
    vim.keymap.set('n', 'gs',   vim.lsp.buf.signature_help, opts)
    vim.keymap.set('n', 'gR',   vim.lsp.buf.rename, opts)
    vim.keymap.set('n', 'ga',   vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gl',   vim.diagnostic.open_float, opts)
    vim.keymap.set('n', '[d',   vim.diagnostic.goto_prev, opts)
    vim.keymap.set('n', ']d',   vim.diagnostic.goto_next, opts)
end

-- Export the function globally so it can be used by ftplugin files
_G.setup_lsp_keybindings = setup_lsp_keybindings

-- Common on_attach function
local on_attach = function(client, bufnr)
    setup_lsp_keybindings(bufnr)
end

-- Setup Mason LSPConfig
mason_lspconfig.setup({
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
        'pylsp',
        -- 'clangd', -- Let's use the system clangd
        -- 'jdtls', -- I'll roll this one manually to get more control.. java..
    },
})

-- Configure individual LSP servers
-- lua_ls
lspconfig.lua_ls.setup({
    on_attach = on_attach,
    capabilities = capabilities,
    settings = {
        Lua = {
            diagnostics = {
                globals = { 'vim' }
            }
        }
    }
})

-- gopls
lspconfig.gopls.setup({
    on_attach = on_attach,
    capabilities = capabilities,
    root_dir = lspconfig.util.root_pattern('go.work', 'go.mod', '.git'),
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

-- pylsp
lspconfig.pylsp.setup({
    on_attach = on_attach,
    capabilities = capabilities,
    settings = {
        pylsp = {
            plugins = {
                -- Built-in plugins are enabled by default
                -- You can adjust specific ones if needed
                pycodestyle = {
                    maxLineLength = 90  -- Adjust to your preference
                }
            }
        }
    }
})

-- Setup servers that don't have custom configuration
local servers = {
    'rust_analyzer',
    'ts_ls',
    'eslint',
    'bashls',
    'yamlls',
    'gradle_ls',
    'marksman',
}

for _, server in ipairs(servers) do
    lspconfig[server].setup({
        on_attach = on_attach,
        capabilities = capabilities,
    })
end

-- Setup Mason DAP
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