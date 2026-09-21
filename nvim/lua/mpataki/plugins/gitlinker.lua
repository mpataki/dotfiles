-- Pin links to a commit SHA so they don't rot when the branch moves.
-- Resolve the SHA from the buffer's own directory: nvim's cwd is often a
-- different repo, which yields a SHA gitlinker can't find the file in.
local function git_link(open)
  return function()
    local dir = vim.fn.expand('%:p:h')
    if dir == '' then
      vim.notify('gitlinker: buffer has no file on disk', vim.log.levels.WARN)
      return
    end

    local out = vim.system({ 'git', '-C', dir, 'rev-parse', 'HEAD' }, { text = true }):wait()
    if out.code ~= 0 then
      vim.notify('gitlinker: not a git repo: ' .. dir, vim.log.levels.WARN)
      return
    end

    vim.cmd('GitLink' .. (open and '!' or '') .. ' rev=' .. vim.trim(out.stdout))
  end
end

return {
  'linrongbin16/gitlinker.nvim',
  cmd = 'GitLink',
  keys = {
    { '<Leader>gl', git_link(false), mode = { 'n', 'v' }, desc = 'Copy git link' },
    { '<Leader>gL', git_link(true), mode = { 'n', 'v' }, desc = 'Open git link' },
  },
}
