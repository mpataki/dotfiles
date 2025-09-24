vim.opt_local.spell = true
vim.opt_local.spelllang = 'en_ca,en_gb'
vim.opt_local.wrap = true
vim.opt_local.linebreak = true

-- Simple spell suggestion popup
vim.keymap.set('n', '<leader>z', function()
  local word = vim.fn.expand('<cword>')
  local suggestions = vim.fn.spellsuggest(word, 10)

  if #suggestions == 0 then return end

  vim.ui.select(suggestions, {
    prompt = "Spell suggestions for: " .. word
  }, function(choice)
    if choice then vim.cmd("normal ciw" .. choice) end
  end)
end, { buffer = true, desc = "Spell Suggestions" })

-- Quick TODO checkbox keybindings (only in markdown files)
local function set_checkbox_state(target_state)
  local current_line = vim.api.nvim_get_current_line()
  local checkbox_pattern = '%- %[.-%]'

  if current_line:match(checkbox_pattern) then
    local new_line = current_line:gsub(checkbox_pattern, '- [' .. target_state .. ']')
    vim.api.nvim_set_current_line(new_line)
  end
end

vim.keymap.set('n', '<Space>j', function() set_checkbox_state('x') end, { buffer = true, desc = "Check TODO item" })
vim.keymap.set('n', '<Space>l', function() set_checkbox_state('-') end, { buffer = true, desc = "Cancel TODO item" })
vim.keymap.set('n', '<Space>k', function() set_checkbox_state('>') end, { buffer = true, desc = "Carry forward TODO item" })
vim.keymap.set('n', '<Space>h', function() set_checkbox_state(' ') end, { buffer = true, desc = "Clear TODO item" })
