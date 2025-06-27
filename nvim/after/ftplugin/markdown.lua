-- Markdown specific settings

-- Setup LSP keybindings if available
if _G.setup_lsp_keybindings then
    vim.api.nvim_create_autocmd('LspAttach', {
        buffer = 0,
        callback = function(args)
            _G.setup_lsp_keybindings(args.buf)
        end
    })
end