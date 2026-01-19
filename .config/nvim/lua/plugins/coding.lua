return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		build = ":TSUpdate",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("nvim-treesitter").setup({})

			-- Enable treesitter for specific languages (official recommended approach)
			-- This prevents the autocmd from firing on UI buffers like blink-cmp-menu
			vim.api.nvim_create_autocmd("FileType", {
				pattern = {
					-- Neovim/Lua development
					"lua",
					"vim",
					"vimdoc",
					"query",
					-- Elixir
					"elixir",
					"heex",
					"eex",
					-- JavaScript/TypeScript
					"javascript",
					"typescript",
					"javascriptreact",
					"typescriptreact",
					"jsx",
					"tsx",
					-- Web
					"html",
					"css",
					"scss",
					"json",
					"jsonc",
					-- Python
					"python",
					-- Markdown
					"markdown",
					"markdown_inline",
					-- Shell
					"bash",
					"sh",
					"zsh",
					-- C/C++
					"c",
					"cpp",
					"h",
					-- Docker
					"dockerfile",
					-- Git (if you want syntax highlighting in commit messages)
					"gitcommit",
					"gitrebase",
					"gitconfig",
					-- Other
					"yaml",
					"toml",
					"sql",
				},
				callback = function()
					vim.treesitter.start()
				end,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
		},
		event = { "BufReadPost", "BufNewFile" },
		branch = "main",
		config = function()
			-- Setup textobjects (new main branch API)
			require("nvim-treesitter-textobjects").setup({
				select = {
					include_surrounding_whitespace = true,
					lookahead = true,
					selection_modes = {
						["@parameter.outer"] = "v", -- charwise
						["@function.outer"] = "V", -- linewise
						["@class.outer"] = "<c-v>", -- blockwise
					},
				},
			})

			-- Manual keymaps for SELECT textobjects (new API requirement)
			local select = require("nvim-treesitter-textobjects.select")

			vim.keymap.set({ "x", "o" }, "af", function()
				select.select_textobject("@function.outer", "textobjects")
			end, { desc = "Select around function" })

			vim.keymap.set({ "x", "o" }, "if", function()
				select.select_textobject("@function.inner", "textobjects")
			end, { desc = "Select inner function" })

			vim.keymap.set({ "x", "o" }, "ac", function()
				select.select_textobject("@class.outer", "textobjects")
			end, { desc = "Select around class" })

			vim.keymap.set({ "x", "o" }, "ic", function()
				select.select_textobject("@class.inner", "textobjects")
			end, { desc = "Select inner class" })

			vim.keymap.set({ "x", "o" }, "ab", function()
				select.select_textobject("@block.outer", "textobjects")
			end, { desc = "Select around block" })

			vim.keymap.set({ "x", "o" }, "ib", function()
				select.select_textobject("@block.inner", "textobjects")
			end, { desc = "Select inner block" })

			vim.keymap.set({ "x", "o" }, "as", function()
				select.select_textobject("@local.scope", "locals")
			end, { desc = "Select language scope" })

			-- Manual keymaps for SWAP textobjects (using ]a/[a to match ] and [ navigation)
			local swap = require("nvim-treesitter-textobjects.swap")

			vim.keymap.set("n", "]a", function()
				swap.swap_next("@parameter.inner")
			end, { desc = "Swap parameter with next" })

			vim.keymap.set("n", "[a", function()
				swap.swap_previous("@parameter.inner")
			end, { desc = "Swap parameter with previous" })
		end,
	},
	{
		"MagicDuck/grug-far.nvim",
		enabled = true,
		opts = { headerMaxWidth = 80 },
		cmd = "GrugFar",
		keys = {
			{
				"<localleader>sr",
				function()
					local grug = require("grug-far")
					local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
					grug.open({
						transient = true,
						prefills = {
							filesFilter = ext and ext ~= "" and "*." .. ext or nil,
						},
					})
				end,
				mode = { "n", "v" },
				desc = "Search and Replace",
			},
		},
	},
	{
		"saghen/blink.compat",
		enabled = true,
		-- use the latest release, via version = '*', if you also use the latest release for blink.cmp
		version = "*",
		-- lazy.nvim will automatically load the plugin when it's required by blink.cmp
		lazy = true,
		-- make sure to set opts so that lazy.nvim calls blink.compat's setup
		opts = {},
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
