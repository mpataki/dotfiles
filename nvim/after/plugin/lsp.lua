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

-- Native diagnostic keymaps (alternative to trouble.nvim)
-- These provide workspace-wide and buffer-specific diagnostic views
-- Usage: <leader>x followed by q/l/e/w/d/D
-- Quickfix list navigation: :cnext, :cprev, :copen, :cclose (or ]q, [q with vim-unimpaired)
-- Location list navigation: :lnext, :lprev, :lopen, :lclose (or ]l, [l with vim-unimpaired)
vim.keymap.set('n', '<leader>xq', function()
    vim.diagnostic.setqflist({ title = "Workspace Diagnostics" })
end, { desc = "Show all workspace diagnostics in quickfix" })

vim.keymap.set('n', '<leader>xl', function()
    vim.diagnostic.setloclist({ title = "Buffer Diagnostics" })
end, { desc = "Show buffer diagnostics in location list" })

-- Filtered diagnostic views
vim.keymap.set('n', '<leader>xe', function()
    vim.diagnostic.setqflist({
        severity = vim.diagnostic.severity.ERROR,
        title = "Workspace Errors"
    })
end, { desc = "Show only errors (workspace)" })

vim.keymap.set('n', '<leader>xw', function()
    vim.diagnostic.setqflist({
        severity = { min = vim.diagnostic.severity.WARN },
        title = "Workspace Warnings+"
    })
end, { desc = "Show warnings and errors (workspace)" })

-- Additional useful diagnostic keymaps
vim.keymap.set('n', '<leader>xd', vim.diagnostic.disable, { desc = "Disable diagnostics" })
vim.keymap.set('n', '<leader>xD', vim.diagnostic.enable, { desc = "Enable diagnostics" })

-- Quickfix and location list navigation helpers
vim.keymap.set('n', ']q', vim.cmd.cnext, { desc = "Next quickfix item" })
vim.keymap.set('n', '[q', vim.cmd.cprev, { desc = "Previous quickfix item" })
vim.keymap.set('n', ']l', vim.cmd.lnext, { desc = "Next location list item" })
vim.keymap.set('n', '[l', vim.cmd.lprev, { desc = "Previous location list item" })

-- Toggle quickfix and location list
vim.keymap.set('n', '<leader>qo', function()
    local qf_exists = false
    for _, win in pairs(vim.fn.getwininfo()) do
        if win["quickfix"] == 1 then
            qf_exists = true
        end
    end
    if qf_exists then
        vim.cmd.cclose()
    else
        vim.cmd.copen()
    end
end, { desc = "Toggle quickfix list" })

vim.keymap.set('n', '<leader>lo', function()
    local loc_exists = false
    for _, win in pairs(vim.fn.getwininfo()) do
        if win["loclist"] == 1 then
            loc_exists = true
        end
    end
    if loc_exists then
        vim.cmd.lclose()
    else
        vim.cmd.lopen()
    end
end, { desc = "Toggle location list" })

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

-- Configure individual LSP servers using native vim.lsp.config
-- lua_ls
vim.lsp.config('lua_ls', {
    cmd = { 'lua-language-server' },
    filetypes = { 'lua' },
    root_markers = { '.luarc.json', '.luarocks', '.git' },
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
vim.lsp.config('gopls', {
    cmd = { 'gopls' },
    filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
    root_markers = { 'go.work', 'go.mod', '.git' },
    on_attach = on_attach,
    capabilities = capabilities,
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
vim.lsp.config('pylsp', {
    cmd = { 'pylsp' },
    filetypes = { 'python' },
    root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git' },
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

-- rust_analyzer
vim.lsp.config('rust_analyzer', {
    cmd = { 'rust-analyzer' },
    filetypes = { 'rust' },
    root_markers = { 'Cargo.toml', '.git' },
    on_attach = on_attach,
    capabilities = capabilities,
})

-- ts_ls (TypeScript Language Server)
vim.lsp.config('ts_ls', {
    cmd = { 'typescript-language-server', '--stdio' },
    filetypes = { 'javascript', 'javascriptreact', 'javascript.jsx', 'typescript', 'typescriptreact', 'typescript.tsx' },
    root_markers = { 'package.json', 'tsconfig.json', 'jsconfig.json', '.git' },
    on_attach = on_attach,
    capabilities = capabilities,
})

-- eslint
vim.lsp.config('eslint', {
    cmd = { 'vscode-eslint-language-server', '--stdio' },
    filetypes = { 'javascript', 'javascriptreact', 'javascript.jsx', 'typescript', 'typescriptreact', 'typescript.tsx', 'vue', 'svelte', 'astro' },
    root_markers = { '.eslintrc', '.eslintrc.js', '.eslintrc.cjs', '.eslintrc.yaml', '.eslintrc.yml', '.eslintrc.json', 'package.json', '.git' },
    on_attach = function(client, bufnr)
        -- Disable ESLint diagnostics to avoid path errors
        client.server_capabilities.diagnosticProvider = false
        on_attach(client, bufnr)
    end,
    capabilities = capabilities,
})

-- bashls
vim.lsp.config('bashls', {
    cmd = { 'bash-language-server', 'start' },
    filetypes = { 'sh', 'bash' },
    root_markers = { '.git' },
    on_attach = on_attach,
    capabilities = capabilities,
})

-- yamlls
vim.lsp.config('yamlls', {
    cmd = { 'yaml-language-server', '--stdio' },
    filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab' },
    root_markers = { '.git' },
    on_attach = on_attach,
    capabilities = capabilities,
})

-- gradle_ls
vim.lsp.config('gradle_ls', {
    cmd = { 'gradle-language-server' },
    filetypes = { 'gradle', 'gradle.kotlin' },
    root_markers = { 'settings.gradle', 'settings.gradle.kts', '.git' },
    on_attach = on_attach,
    capabilities = capabilities,
})

-- marksman
vim.lsp.config('marksman', {
    cmd = { 'marksman', 'server' },
    filetypes = { 'markdown', 'markdown.mdx' },
    root_markers = { '.marksman.toml', '.git' },
    on_attach = on_attach,
    capabilities = capabilities,
})

-- Enable all configured servers
local servers = {
    'lua_ls',
    'gopls',
    'pylsp',
    'rust_analyzer',
    'ts_ls',
    'eslint',
    'bashls',
    'yamlls',
    'gradle_ls',
    'marksman',
}

for _, server in ipairs(servers) do
    vim.lsp.enable(server)
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