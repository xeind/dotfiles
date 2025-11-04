return {
	{
		"xeind/nightingale.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("nightingale").setup({
				compile = true,
				transparent = false,
				overrides = function(colors)
					return {
						SpellBad = { undercurl = true, sp = colors.palette.gray },

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
