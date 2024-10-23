-- entirely possible I should nix this thing. It breaks a lot on reloads. 
return {
    {
        'dsych/blanket.nvim',
        lazy = false,
        config = function()
            local blanket = require("blanket")

            blanket.setup({
                -- can use env variables and anything that could be interpreted by expand(), see :h expandcmd()
                -- OPTIONAL
                report_path = vim.fn.getcwd().."/build/reports/jacoco/test/jacocoTestReport.xml",
                -- refresh gutter every time we enter java file
                -- defauls to empty - no autocmd is created
                filetypes = "java",
                -- for debugging purposes to see whether current file is present inside the report
                -- defaults to false
                silent = true,
                -- can set the signs as well
                signs = {
                    priority = 10,
                    incomplete_branch = "█",
                    uncovered = "█",
                    covered = "█",
                    sign_group = "Blanket",

                    -- and the highlights for each sign!
                    -- useful for themes where below highlights are similar
                    incomplete_branch_color = "WarningMsg",
                    -- covered_color = "Statement", -- the default
                    covered_color = "String", -- happens to be green in my colour scheme
                    uncovered_color = "Error",
                },
            })

            require('blanket').stop() -- prevent auto-start...
            CODE_COVERAGE_STARTED = false;

            vim.keymap.set('n', '<Leader>cc', function()
                if CODE_COVERAGE_STARTED then
                    blanket.stop()
                    CODE_COVERAGE_STARTED = false;
                else
                    blanket.pick_report_path() -- refresh the report
                    blanket.start()
                    CODE_COVERAGE_STARTED = true;
                end
            end)
        end
    },
}
