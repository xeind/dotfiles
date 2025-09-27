return {
	{
		"rebelot/kanagawa.nvim",
		lazy = false,
		config = function()
			require("kanagawa").setup({
				compile = true,
				transparent = true,

				overrides = function(colors)
					local palette = colors.palette
					return {
						-- Diagnostics
						SpellBad = { undercurl = true, sp = palette.dragonAsh },

						-- Markdown
						["@markup.link.url.markdown_inline"] = { link = "Special" }, -- (url)
						["@markup.link.label.markdown_inline"] = { link = "WarningMsg" }, -- [label]
						["@markup.italic.markdown_inline"] = { link = "Exception" }, -- *italic*
						["@markup.raw.markdown_inline"] = { link = "String" }, -- `code`
						["@markup.list.markdown"] = { link = "Function" }, -- + list
						["@markup.quote.markdown"] = { link = "Error" }, -- > blockcode
						["@markup.list.checked.markdown"] = { link = "WarningMsg" }, -- > blockcode

						-- Completion menu
						BlinkCmpMenu = { bg = palette.dragonBlack3, fg = palette.fujiWhite },
						BlinkCmpMenuBorder = { bg = palette.dragonBlack3, fg = palette.dragonBlack5 },
						BlinkCmpMenuSelection = { bg = palette.waveBlue2, fg = palette.fujiWhite, bold = true },

						-- Scrollbar
						BlinkCmpScrollBarGutter = { bg = palette.waveBlue1 },
						BlinkCmpScrollBarThumb = { bg = palette.waveBlue2 },

						-- Labels
						BlinkCmpLabel = { fg = palette.fujiWhite },
						BlinkCmpLabelMatch = { fg = palette.waveRed, bold = true },
						BlinkCmpLabelDeprecated = { fg = palette.katanaGray, strikethrough = true },
						BlinkCmpLabelDetail = { fg = palette.dragonTeal },
						BlinkCmpLabelDescription = { fg = palette.dragonGray2 },

						-- Kind
						BlinkCmpKind = { fg = palette.dragonBlue2 },
						BlinkCmpKindFunction = { fg = palette.dragonBlue2 },
						BlinkCmpKindVariable = { fg = palette.dragonOrange },
						BlinkCmpKindClass = { fg = palette.dragonViolet },
						BlinkCmpKindInterface = { fg = palette.dragonAqua },
						BlinkCmpKindSnippet = { fg = palette.waveRed },
						BlinkCmpKindKeyword = { fg = palette.dragonRed },

						-- Source
						BlinkCmpSource = { fg = palette.dragonGray2 },

						-- Ghost text
						BlinkCmpGhostText = { fg = palette.dragonGray3, italic = true },

						-- Documentation popup
						BlinkCmpDoc = { bg = palette.dragonBlack0, fg = palette.oldWhite },
						BlinkCmpDocBorder = { bg = palette.dragonBlack0, fg = palette.sumiInk6 },
						BlinkCmpDocCursorLine = { bg = palette.waveBlue1, fg = palette.fujiWhite },
						BlinkCmpDocSeparator = { fg = palette.dragonGray3 },

						-- Signature help
						BlinkCmpSignatureHelp = { bg = palette.dragonBlack0, fg = palette.oldWhite },
						BlinkCmpSignatureHelpBorder = { bg = palette.dragonBlack0, fg = palette.sumiInk6 },
						BlinkCmpSignatureHelpActiveParameter = { fg = palette.waveRed, bold = true },

						-- nvim-cmp popup menu
						Pmenu = { fg = palette.oldWhite, bg = palette.dragonBlack3 },
						PmenuSel = { fg = palette.fujiWhite, bg = palette.waveBlue2, bold = true },
						PmenuSbar = { bg = palette.dragonBlack4 },
						PmenuThumb = { bg = palette.waveBlue2 },

						-- Completion item highlights
						CmpItemAbbr = { fg = palette.oldWhite },
						CmpItemAbbrMatch = { fg = palette.lotusRed2, bold = true },
						CmpItemAbbrMatchFuzzy = { fg = palette.waveRed, underline = true },

						CmpItemKind = { fg = palette.springBlue },
						CmpItemMenu = { fg = palette.dragonGray3 },
						CmpItemKindFunction = { fg = palette.springBlue },
						CmpItemKindVariable = { fg = palette.dragonGray3 },
						CmpItemKindKeyword = { fg = palette.dragonGray },

						-- Optional: make doc popup background consistent
						NormalFloat = { bg = palette.dragonBlack3 },
						FloatBorder = { bg = palette.dragonBlack3, fg = palette.dragonGray },
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
		"vague2k/vague.nvim",
		lazy = true, -- make sure we load this during startup if it is your main colorscheme
		enabled = true,
		priority = 1000, -- make sure to load this before all the other plugins
		config = function()
			-- NOTE: you do not need to call setup if you don't want to.
			require("vague").setup({
				-- optional configuration here
				transparent = true,
			})
			vim.cmd("colorscheme vague")
		end,
	},
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
}
