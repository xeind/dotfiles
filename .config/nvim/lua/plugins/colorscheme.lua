return {
	{
		"rebelot/kanagawa.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("kanagawa").setup({
				compile = true,
				transparent = true,
				overrides = function(colors)
					local palette = colors.palette
					local theme   = colors.theme
					return {
						-- Diagnostics
						SpellBad                               = { undercurl = true, sp = palette.dragonAsh },

						-- Markdown
						["@markup.link.url.markdown_inline"]   = { link = "Special" },
						["@markup.link.label.markdown_inline"] = { link = "WarningMsg" },
						["@markup.italic.markdown_inline"]     = { link = "Italic" },
						["@markup.raw.markdown_inline"]        = { link = "String" },
						["@markup.list.markdown"]              = { link = "Function" },
						["@markup.quote.markdown"]             = { link = "Comment" },
						["@markup.list.checked.markdown"]      = { link = "DiagnosticOk" },

						-- Blink / Cmp menu
						BlinkCmpMenu                           = { bg = theme.ui.bg_p2, fg = theme.ui.fg },
						BlinkCmpMenuBorder                     = { fg = theme.ui.bg_m3 },
						BlinkCmpMenuSelection                  = { bg = theme.syn.fun, fg = theme.ui.fg, bold = true },

						-- Scrollbar
						BlinkCmpScrollBarGutter                = { bg = palette.waveBlue1 },
						BlinkCmpScrollBarThumb                 = { bg = palette.waveBlue2 },

						-- Labels
						BlinkCmpLabel                          = { fg = palette.fujiWhite },
						BlinkCmpLabelMatch                     = { fg = palette.waveRed, bold = true },

						-- Popup
						NormalFloat                            = { bg = theme.ui.bg_p1 },
						FloatBorder                            = { bg = theme.ui.bg_p1, fg = theme.ui.bg_m3 },

						-- Transparency consistency
						Normal                                 = { bg = "none" },
						NormalNC                               = { bg = "none" },
						SignColumn                             = { bg = "none" },
					}
				end,
			})
			vim.cmd("colorscheme kanagawa-dragon")
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
