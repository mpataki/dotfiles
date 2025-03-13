vim.opt_local.spell = true
vim.opt_local.spelllang = 'en_ca,en_gb'

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
