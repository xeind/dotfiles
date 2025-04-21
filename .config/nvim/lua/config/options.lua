local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.wrap = false
opt.cursorline = true
opt.signcolumn = "yes"
opt.showmode = false

opt.tabstop = 4
-- opt.softtabstop = 4
-- opt.shiftwidth = 4
-- opt.expandtab = true

opt.smartindent = true
opt.autoindent = true

opt.undofile = true
opt.clipboard = "unnamedplus"
opt.autochdir = false
opt.swapfile = false
opt.timeoutlen = 400
opt.updatetime = 400

opt.listchars = { tab = "▏ ", trail = "·", eol = "¬" }

opt.list = true
opt.ignorecase = true
opt.smartcase = true

opt.splitright = true
opt.splitbelow = true
opt.scrolloff = 6

vim.cmd([[let &t_Cs = "\e[4:3m"]])
vim.cmd([[let &t_Ce = "\e[4:0m"]])
