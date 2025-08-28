local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end

vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " "
vim.g.maplocalleader = ","

require("config.options")
require("config.autocmds")

require("lazy").setup({
	spec = {
		{ import = "plugins" },
	},
	defaults = {},
	performance = {
		rtp = {
			disabled_plugins = {
				"gzip",
				"tarPlugin",
				"tohtml",
				"tutor",
				"zipPlugin",
				"netrwPlugin",
			},
		},
	},
	ui = {
		border = "rounded",
		size = {
			width = 0.8,
			height = 0.8,
		},
	},

	install = { colorscheme = { "kanagawa-dragon" } },
	checker = { enabled = true, notify = false },
})

require("config.keymaps")

vim.cmd([[hi StatusLine guibg=NONE]])
vim.opt.guicursor = ""
