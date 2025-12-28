return {
  'kristijanhusak/vim-dadbod-ui',
  dependencies = {
    { 'tpope/vim-dadbod', lazy = true },
    { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true },
    { 'junegunn/vim-redis', ft = 'redis', lazy = true },
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

    vim.keymap.set('n', '<leader>D', function()
      vim.cmd('tabnew')
      vim.cmd('DBUI')
    end, { desc = 'Open DBUI in new tab' })
  end,
  config = function ()
    local function db_completion()
        require("cmp").setup.buffer { sources = { { name = "vim-dadbod-completion" } } }
    end

    vim.g.db_ui_save_location = vim.fn.expand("~") .. "/obsidian-notes-vault/03-resources/code/db_ui"

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

    -- Apply Redis filetype to Redis buffers from dadbod
    vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*",
        callback = function()
            local bufname = vim.api.nvim_buf_get_name(0)
            -- Check if this is a Redis buffer from dadbod
            if bufname:match("redis://") or bufname:match("%.redis$") then
                vim.bo.filetype = "redis"
            end
        end,
    })
  end
}
