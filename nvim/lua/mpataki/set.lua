vim.g.mapleader = " "

--vim.opt.guicursor = ""

vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

vim.opt.colorcolumn = "90"

-- netrw (the file tree) settings
vim.g.netrw_liststyle = 3
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25
vim.g.netrw_preview = 1
-- vim.g.netrw_browse_split = 4

vim.opt.cursorline = true
vim.api.nvim_set_hl(0, "CursorLine", { bg = "#020202" })

-- Define custom highlight groups for active and inactive splits
vim.api.nvim_set_hl(0, 'ActiveSplit', { bg = '#000000' })
vim.api.nvim_set_hl(0, 'InactiveSplit', { bg = '#151515' })

-- Apply the winhighlight to the current window
vim.wo.winhighlight = 'Normal:ActiveSplit,NormalNC:InactiveSplit'
