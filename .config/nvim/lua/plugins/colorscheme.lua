return {
	{
		"norcalli/nvim-colorizer.lua",
		event = "BufReadPost",
		config = function()
			vim.opt.termguicolors = true
			require("colorizer").setup({
				"*", -- Highlight all files, but customize some specific file types
				css = { css = true }, -- Enable all CSS features: rgb_fn, hsl_fn, names, RRGGBBAA
				html = { names = true }, -- Enable named colors in HTML
			}, {
				mode = "background", -- Set the display mode. Options: 'foreground', 'background'
			})
		end,
	},
	{
		"xeind/nightingale.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("nightingale").setup({
				compile = true,
				transparent = true,
				numberStyle = {},
				overrides = function(colors)
					return {
						SpellBad = { undercurl = true, sp = colors.gray },

						["@markup.link.url.markdown_inline"] = { link = "Special" },
						["@markup.link.label.markdown_inline"] = { link = "WarningMsg" },
						["@markup.italic.markdown_inline"] = { link = "Italic" },
						["@markup.raw.markdown_inline"] = { link = "String" },
						["@markup.list.markdown"] = { link = "Function" },
						["@markup.quote.markdown"] = { link = "Comment" },
						["@markup.list.checked.markdown"] = { link = "DiagnosticOk" },
					}
				end,
			})
			vim.cmd("colorscheme nightingale")
		end,
	},
}
