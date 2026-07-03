return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format({ async = true, lsp_format = 'fallback' })
      end,
      desc = 'Format buffer',
    },
  },
  config = function()
    require('conform').setup({
      format_on_save = function(bufnr)
        -- kulala's LSP formatter rewrites whitespace in ways that break .http
        -- semantics (e.g. blank line between request line and headers).
        local ft = vim.bo[bufnr].filetype
        if ft == 'http' or ft == 'rest' then
          return nil
        end
        return { timeout_ms = 2000, lsp_format = 'fallback' }
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        -- prettier resolves from the repo's local node_modules, so it uses that
        -- project's .prettierrc and does nothing in repos without prettier.
        javascript = { 'prettier' },
        typescript = { 'prettier' },
        javascriptreact = { 'prettier' },
        typescriptreact = { 'prettier' },
        svelte = { 'prettier' },
        css = { 'prettier' },
        scss = { 'prettier' },
        html = { 'prettier' },
        json = { 'prettier' },
        jsonc = { 'prettier' },
        yaml = { 'prettier' },
        markdown = { 'prettier' },
      },
    })
  end,
}
