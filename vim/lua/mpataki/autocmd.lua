vim.api.nvim_create_autocmd("FileType", {
    pattern = "java",
    callback = function()
       vim.bo.formatprg = os.getenv('HOME') .. '/.local/share/nvim/mason/packages/google-java-format/google-java-format -'

       -- set keymap to format the whole buffer
       vim.keymap.set('n', '<leader>f', function()
           vim.cmd('normal gggqG')
       end, { noremap = true, desc = 'Format entire file using formatprg' })

    end
})

