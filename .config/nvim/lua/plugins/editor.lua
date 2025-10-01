return {
	{
		"ibhagwan/fzf-lua",
		cmd = "FzfLua",
		-- event = "VeryLazy",
		dependencies = {
			{ "nvim-tree/nvim-web-devicons" },
		},
		keys = {
			{ "<c-j>", "<c-j>", ft = "fzf", mode = "t", nowait = true },
			{ "<c-k>", "<c-k>", ft = "fzf", mode = "t", nowait = true },
			{
				"<leader>ec",
				function()
					require("fzf-lua").files({
						cwd = vim.fn.stdpath("config"),
						prompt = "Config ",
					})
				end,
				desc = "[E]dit [C]onfig",
			},
			{
				"<leader>ff",
				function()
					require("fzf-lua").files()
				end,
				desc = "[F]ind [F]iles",
			},
			{
				"<leader>fg",
				function()
					require("fzf-lua").live_grep()
				end,
				desc = "[F]ind [G]rep",
			},
			{
				"<leader>fh",
				function()
					require("fzf-lua").helptags()
				end,
				desc = "[F]ind [H]elp",
			},
			{
				"<leader>fk",
				function()
					require("fzf-lua").keymaps()
				end,
				desc = "[F]ind [K]eymaps",
			},
			{
				"<leader>fb",
				function()
					require("fzf-lua").builtin()
				end,
				desc = "[F]ind [B]uiltin FZF",
			},
			{
				"<leader>fw",
				function()
					require("fzf-lua").grep_cword()
				end,
				desc = "[F]ind current [W]ord",
			},
			{
				"<leader>fW",
				function()
					require("fzf-lua").grep_cWORD()
				end,
				desc = "[F]ind current [W]ORD",
			},
			{
				"<leader>fd",
				function()
					require("fzf-lua").diagnostics_document()
				end,
				desc = "[F]ind [D]iagnostics",
			},
			{
				"<leader>fr",
				function()
					require("fzf-lua").resume()
				end,
				desc = "[F]ind [R]esume",
			},
			{
				"<leader>fo",
				function()
					require("fzf-lua").oldfiles()
				end,
				desc = "[F]ind [O]ld Files",
			},
			{
				"<leader>,",
				function()
					require("fzf-lua").buffers()
				end,
				desc = "[F]ind [ ] Buffers",
			},
			{
				"<leader>/",
				function()
					require("fzf-lua").lgrep_curbuf()
				end,
				desc = "[/] Live grep in current Buffer",
			},
			{
				"<leader>gB",
				function()
					require("fzf-lua").git_branches()
				end,
				desc = "Open Git Branches",
			},
		},
		opts = {
			files = {
				fd_opts = table.concat({
					"--hidden",
					"--exclude .git",
					"--exclude node_modules",
					"--exclude dist",
					"--exclude build",
					"--exclude .next",
					"--exclude .nuxt",
					"--exclude .vercel",
					"--exclude .cache",
					"--exclude coverage",
					"--exclude venv",
					"--exclude .venv",
					"--exclude vendor",
				}, " "),
				rg_opts = table.concat({
					"--hidden",
					"--glob '!node_modules/*'",
					"--glob '!.git/*'",
					"--glob '!dist/*'",
					"--glob '!build/*'",
					"--glob '!.next/*'",
					"--glob '!.nuxt/*'",
					"--glob '!.vercel/*'",
					"--glob '!.cache/*'",
					"--glob '!coverage/*'",
					"--glob '!venv/*'",
					"--glob '!.venv/*'",
					"--glob '!.vendor/*'",
				}, " "),
			},
			grep = {
				rg_opts = table.concat({
					"--hidden",
					"--glob '!node_modules/*'",
					"--glob '!.git/*'",
					"--glob '!dist/*'",
					"--glob '!build/*'",
					"--glob '!.next/*'",
					"--glob '!.nuxt/*'",
					"--glob '!.vercel/*'",
					"--glob '!.cache/*'",
					"--glob '!coverage/*'",
					"--glob '!venv/*'",
					"--glob '!.venv/*'",
					"--column",
					"--line-number",
					"--no-heading",
					"--color=always",
					"--smart-case",
				}, " "),
			},
		},
	},
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		---@type Flash.Config
		opts = {
			labels = "asdfqwerzxcv",
			modes = {
				cmdline = { enabled = true },
			},
		},
		-- stylua: ignore
		keys = {
			{ "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
			{ "S",     mode = { "n", "o" },      function() require("flash").treesitter() end,        desc = "Flash Treesitter" },
			{ "r",     mode = "o",               function() require("flash").remote() end,            desc = "Remote Flash" },
			{ "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
			{ "<C-s>", mode = { "c" },           function() require("flash").toggle() end,            desc = "Toggle Flash Search" },
		},
	},
	{
		"stevearc/conform.nvim",
		events = "VeryLazy",
		ft = { "ruby" },
		opts = {
			formatters_by_ft = {
				lua = { "stylua" },
				json = { "jq", "prettierd" },
				tex = {},
				python = { "black" },
				javascript = { "prettierd" },
				typescript = { "prettierd" },
				typescriptreact = { "prettierd" },
				vue = { "prettierd" },
				typst = { "typstyle" },
				markdown = { "prettierd", "prettier" },
				cpp = {},
				latex = { "latexindent" },
				ruby = { "rubocop" },
				eruby = { "erb_format" },
				--	typescriptreact = { "typescript_tool",  },
			},
			-- Place this outside the table, in the `opts`
			-- format_opts = {
			-- 	javascript = { stop_after_first = true },
			-- 	typescript = { stop_after_first = true },
			-- 	typescriptreact = { stop_after_first = true },
			-- 	markdown = { stop_after_first = true },
			-- },
			format_on_save = {
				-- lsp_format = true,
				lsp_fallback = true,
				timeout_ms = 400,
			},
		},
		keys = {
			{
				"<leader>cf",
				function()
					require("conform").format({
						lsp_format = "fallback",
					})
				end,
				mode = { "n", "v" },
				desc = "Format on save",
			},
		},
	},
	{
		"folke/trouble.nvim",
		opts = {}, -- for default options, refer to the configuration section for custom setup.
		cmd = "Trouble",
		keys = {
			{
				"<leader>xx",
				"<cmd>Trouble diagnostics toggle<cr>",
				desc = "Diagnostics (Trouble)",
			},
			{
				"<leader>xX",
				"<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
				desc = "Buffer Diagnostics (Trouble)",
			},
			{
				"<leader>cs",
				"<cmd>Trouble symbols toggle focus=false win.position=right<cr>",
				desc = "Symbols (Trouble)",
			},
			{
				"<leader>cl",
				"<cmd>Trouble lsp toggle focus=false win.position=bottom<cr>",
				desc = "LSP Definitions / references / ... (Trouble)",
			},
			{
				"<leader>xL",
				"<cmd>Trouble loclist toggle<cr>",
				desc = "Location List (Trouble)",
			},
			{
				"<leader>xQ",
				"<cmd>Trouble qflist toggle<cr>",
				desc = "Quickfix List (Trouble)",
			},
		},
	},
	{
		"kylechui/nvim-surround",
		version = "^3.0.0", -- use for stability; omit to use `main` branch for the latest features
		event = "VeryLazy",
		config = function()
			require("nvim-surround").setup({
				-- configuration here, or leave empty to use defaults
			})
		end,
	},
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {},
	},
	{
		"lervag/vimtex",
		-- lazy = false, -- we don't want to lazy load VimTeX
		ft = { "tex", "plaintex", "bib" },
		-- tag = "v2.15", -- uncomment to pin to a specific release
		init = function()
			-- VimTeX configuration goes here, e.g.
			vim.g.vimtex_view_method = "skim"
			vim.g.context_pdf_viewer = "skim"
			vim.g.vimtex_compiler_method = "latexmk"
		end,
	},
	{
		"chomosuke/typst-preview.nvim",
		-- lazy = false, -- or ft = 'typst'
		ft = "typst",
		version = "1.*",
		opts = {}, -- lazy.nvim will implicitly calls `setup {}`
		config = function() end,
	},
}
