return {
  'ray-x/lsp_signature.nvim',
  event = 'LspAttach',
  config = function()
    require('lsp_signature').setup({
      bind = true,
      handler_opts = {
        border = 'rounded'
      },
      hint_enable = false,  -- Disable virtual text hints
      floating_window = true,
      floating_window_above_cur_line = true,
      toggle_key = '<C-k>',  -- Manual toggle in insert mode
      select_signature_key = '<C-n>',  -- Cycle between overloads if multiple exist
    })
  end
}
