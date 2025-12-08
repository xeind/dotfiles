return {
	{
		"xeind/nightingale.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("nightingale").setup({
				compile = true,
				transparent = true,
			})
			vim.cmd("colorscheme nightingale")
		end,
	},
}
