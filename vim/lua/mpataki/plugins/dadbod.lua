return {
  'kristijanhusak/vim-dadbod-ui',
  dependencies = {
    { 'tpope/vim-dadbod', lazy = true },
    { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true },
  },
  cmd = {
    'DBUI',
    'DBUIToggle',
    'DBUIAddConnection',
    'DBUIFindBuffer',
  },
  init = function()
    -- Your DBUI configuration
    vim.g.db_ui_use_nerd_fonts = 1
    vim.api.nvim_set_hl(0, 'NotificationInfo', { fg = '#63ff00', bg = '#000000', italic = true })
    vim.api.nvim_set_hl(0, 'NotificationWarning', { fg = '#FFA500', bg = '#000000', italic = true })
    vim.api.nvim_set_hl(0, 'NotificationError', { fg = '#ff2f2f', bg = '#000000', italic = true })

    end,
  config = function ()
    local function db_completion()
        require("cmp").setup.buffer { sources = { { name = "vim-dadbod-completion" } } }
    end

    -- vim.g.db_ui_save_location = vim.fn.stdpath "config" .. require("plenary.path").path.sep .. "db_ui"

    vim.api.nvim_create_autocmd("FileType", {
        pattern = {
            "sql",
        },
        command = [[setlocal omnifunc=vim_dadbod_completion#omni]],
    })

    vim.api.nvim_create_autocmd("FileType", {
        pattern = {
            "sql",
            "mysql",
            "plsql",
        },
        callback = function()
            vim.schedule(db_completion)
        end,
    })
  end
}
