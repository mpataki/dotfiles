-- paste without losing what's in the yank buffer
vim.keymap.set("x", "<leader>p", [["_dP]])

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- copy to mac clipboard
vim.keymap.set({ "n", "v" }, "<leader>y", '"+y')
vim.keymap.set("n", "<leader>Y", '"+Y')

vim.keymap.set("n", "<leader>f", vim.lsp.buf.format)

-- terminal
vim.keymap.set('t', '<Esc>', '<C-\\><C-n>')

-- split resizing
vim.keymap.set("n", "<MC-h>", "<c-w>5<")
vim.keymap.set("n", "<MC-l>", "<c-w>5>")
vim.keymap.set("n", "<MC-k>", "<C-w>+")
vim.keymap.set("n", "<MC-j>", "<C-w>-")

-- next and previous buffers
vim.keymap.set("n", '<leader>n', ":bnext<CR>")
vim.keymap.set("n", '<leader>p', ":bprevious<CR>")

-- next and previous jump
vim.keymap.set("n", '<c-o>', "<c-o>zz");
vim.keymap.set("n", '<c-i>', "<c-i>zz");

-- quickfix
vim.keymap.set("n", "<leader>co", ":copen<CR>")
vim.keymap.set("n", "<leader>cc", ":cclose<CR>")
vim.keymap.set("n", "<leader>cq", ":cclose<CR>")
vim.keymap.set("n", "<leader>cn", ":cnext<CR>")
vim.keymap.set("n", "<leader>cp", ":cprev<CR>")

vim.keymap.set("n", "<leader>w", ":w<CR>", { nowait = true, silent = true })
vim.keymap.set("n", "<leader>q", ":q<CR>", { nowait = true, silent = true })
vim.keymap.set("n", "<leader>sv", ":vsplit<CR><C-w>l");
vim.keymap.set("n", "<leader>sh", ":split<CR><C-w>j");
