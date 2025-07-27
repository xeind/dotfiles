return {
	{
		"rebelot/kanagawa.nvim",
		config = function()
			require("kanagawa").setup({
				enabled = false,
				compile = true,
				transparent = true,

				overrides = function(colors)
					return {
						-- Diagnostics
						SpellBad = { undercurl = true, sp = colors.palette.dragonAsh },

						-- Markdown
						["@markup.link.url.markdown_inline"] = { link = "Special" }, -- (url)
						["@markup.link.label.markdown_inline"] = { link = "WarningMsg" }, -- [label]
						["@markup.italic.markdown_inline"] = { link = "Exception" }, -- *italic*
						["@markup.raw.markdown_inline"] = { link = "String" }, -- `code`
						["@markup.list.markdown"] = { link = "Function" }, -- + list
						["@markup.quote.markdown"] = { link = "Error" }, -- > blockcode
						["@markup.list.checked.markdown"] = { link = "WarningMsg" }, -- > blockcode
					}
				end,
			})
			vim.cmd("colorscheme kanagawa-dragon")
		end,
		build = function()
			vim.cmd("KanagawaCompile")
		end,
	},
	{
		"norcalli/nvim-colorizer.lua",
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
}
