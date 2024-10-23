-- set external formatter to the google java formatter, as installed by mason, for java files
vim.api.nvim_create_autocmd("FileType", {
    pattern = "java",
    callback = function()
        vim.bo.formatprg = os.getenv('HOME') .. '/.local/share/nvim/mason/bin/google-java-format -'
    end
})
