return {
  "coder/claudecode.nvim",
  config = {
    terminal = {
      provider = "none",
    },
    diff_opts = {
      layout = "horizontal",
    },
  },
  keys = {
    { "<leader>c", nil, desc = "AI/Claude Code" },
    { "<leader>cb", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer" },
    { "<leader>cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
    { "<leader>ca", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
    { "<leader>cd", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
  },
}
