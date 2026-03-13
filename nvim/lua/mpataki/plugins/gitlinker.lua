return {
  'linrongbin16/gitlinker.nvim',
  cmd = 'GitLink',
  opts = {
    router = {
      browse = {
        ["^gitlab%.1password%.io"] = "https://gitlab.1password.io/"
          .. "{_A.ORG}/"
          .. "{_A.REPO}/-/blob/"
          .. "{_A.REV}/"
          .. "{_A.FILE}"
          .. "#L{_A.LSTART}"
          .. "{(_A.LEND > _A.LSTART and ('-L' .. _A.LEND) or '')}",
      },
      blame = {
        ["^gitlab%.1password%.io"] = "https://gitlab.1password.io/"
          .. "{_A.ORG}/"
          .. "{_A.REPO}/-/blame/"
          .. "{_A.REV}/"
          .. "{_A.FILE}"
          .. "#L{_A.LSTART}"
          .. "{(_A.LEND > _A.LSTART and ('-L' .. _A.LEND) or '')}",
      },
    },
  },
  keys = {
    { '<Leader>gl', '<cmd>GitLink<cr>', mode = { 'n', 'v' }, desc = 'Copy git link' },
    { '<Leader>gL', '<cmd>GitLink!<cr>', mode = { 'n', 'v' }, desc = 'Open git link' },
  },
}
