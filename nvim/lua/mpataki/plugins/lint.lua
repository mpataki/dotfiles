return {
  'mfussenegger/nvim-lint',
  event = { 'BufReadPost', 'BufWritePost' },
  config = function()
    local lint = require('lint')

    lint.linters_by_ft = {
      sh = { 'shellcheck' },
      go = { 'golangcilint' },
      dockerfile = { 'hadolint' },
      markdown = { 'markdownlint' },
    }

    vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
      group = vim.api.nvim_create_augroup('nvim-lint', { clear = true }),
      callback = function()
        lint.try_lint()

        -- actionlint for GitHub Actions workflow files
        if vim.fn.expand('%:p'):match('%.github/workflows/') then
          lint.try_lint('actionlint')
        end
      end,
    })

    -- zizmor: security scanner, run on demand with :LintSecurity
    vim.api.nvim_create_user_command('LintSecurity', function()
      if vim.fn.expand('%:p'):match('%.github/workflows/') then
        lint.try_lint('zizmor')
      else
        print('LintSecurity: not a GitHub Actions workflow file')
      end
    end, { desc = 'Run zizmor security scan on workflow file' })
  end,
}
