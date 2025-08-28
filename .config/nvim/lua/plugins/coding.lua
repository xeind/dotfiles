return {
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSupdate",
		-- lazy = false,
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local configs = require("nvim-treesitter.configs")

			configs.setup({
				ensure_installed = {
					"c",
					"lua",
					"vim",
					"vimdoc",
					"query",
					"elixir",
					"heex",
					"javascript",
					"html",
					"json5",
					"python",
					"markdown",
					"dockerfile",
				},
				auto_install = true,
				sync_install = false,
				highlight = {
					enable = true,
					additional_vim_regex_highlighting = false,
				},
				indent = { enable = true },

				-- Select through <CR>
				incremental_selection = {
					enable = true,
					keymaps = {
						init_selection = "<enter>",
						node_incremental = "<enter>",
						scope_incremental = false,
						node_decremental = "<backspace>",
					},
				},
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		enabled = true,
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
		},
		event = { "BufReadPost", "BufNewFile" },

		config = function()
			local config = require("nvim-treesitter.configs")
			config.setup({
				textobjects = {
					select = {
						enable = true,

						-- automatically jump forward to textobj, similar to targets.vim
						lookahead = true,

						keymaps = {
							-- you can use the capture groups defined in textobjects.scm
							["af"] = "@function.outer",
							["if"] = "@function.inner",
							["ac"] = "@class.outer",
							-- you can optionally set descriptions to the mappings (used in the desc parameter of
							-- nvim_buf_set_keymap) which plugins like which-key display
							["ic"] = { query = "@class.inner", desc = "select inner part of a class region" },
							-- you can also use captures from other query groups like `locals.scm`
							["as"] = { query = "@local.scope", query_group = "locals", desc = "select language scope" },
							["ab"] = "@block.outer",
							["ib"] = "@block.inner",
						},
						-- you can choose the select mode (default is charwise 'v')
						--
						-- can also be a function which gets passed a table with the keys
						-- * query_string: eg '@function.inner'
						-- * method: eg 'v' or 'o'
						-- and should return the mode ('v', 'v', or '<c-v>') or a table
						-- mapping query_strings to modes.
						selection_modes = {
							["@parameter.outer"] = "v", -- charwise
							["@function.outer"] = "v", -- linewise
							["@class.outer"] = "<c-v>", -- blockwise
						},
						-- if you set this to `true` (default is `false`) then any textobject is
						-- extended to include preceding or succeeding whitespace. succeeding
						-- whitespace has priority in order to act similarly to eg the built-in
						-- `ap`.
						--
						-- can also be a function which gets passed a table with the keys
						-- * query_string: eg '@function.inner'
						-- * selection_mode: eg 'v'
						-- and should return true or false
						include_surrounding_whitespace = true,
					},
					swap = {
						enable = true,
						swap_next = {
							["<leader>a"] = { query = "@parameter.inner", desc = "Swap with next parameter" },
						},
						swap_previous = {
							["<leader>A"] = { query = "@parameter.inner", desc = "Swap with previous parameter" },
						},
					},
				},
			})
		end,
	},
	{
		"MagicDuck/grug-far.nvim",
		enabled = false,
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
}
