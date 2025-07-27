return {
	{
		"kdheepak/lazygit.nvim",
		events = "VeryLazy",
		lazy = true,
		cmd = {
			"LazyGit",
			"LazyGitConfig",
			"LazyGitCurrentFile",
			"LazyGitFilter",
			"LazyGitFilterCurrentFile",
		},
		-- optional for floating window border decoration
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
		-- setting the keybinding for LazyGit with 'keys' is recommended in
		-- order to load the plugin when the command is run for the first time
		keys = {
			{ "<leader>lg", "<cmd>LazyGit<cr>", desc = "Open [L]azy[G]it" },
			{ "<leader>gl", "<cmd>LazyGitLog<cr>", desc = "Open [G]it [L]ogs" },
		},
	},
	{
		"lewis6991/gitsigns.nvim",
		config = function()
			require("gitsigns").setup({
				on_attach = function(bufnr)
					local gitsigns = require("gitsigns")

					local function map(mode, l, r, opts)
						opts = opts or {}
						opts.buffer = bufnr
						vim.keymap.set(mode, l, r, opts)
					end

					-- Navigation
					map("n", "]c", function()
						if vim.wo.diff then
							vim.cmd.normal({ "]c", bang = true })
						else
							gitsigns.nav_hunk("next")
						end
					end, { desc = "Next Git hunk or diff" })

					map("n", "[c", function()
						if vim.wo.diff then
							vim.cmd.normal({ "[c", bang = true })
						else
							gitsigns.nav_hunk("prev")
						end
					end, { desc = "Previous Git hunk or diff" })

					-- Actions
					map("n", "<leader>hs", gitsigns.stage_hunk, { desc = "Stage hunk" })
					map("n", "<leader>hr", gitsigns.reset_hunk, { desc = "Reset hunk" })

					map("v", "<leader>hs", function()
						gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end, { desc = "Stage selected hunk" })

					map("v", "<leader>hr", function()
						gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end, { desc = "Reset selected hunk" })

					map("n", "<leader>hS", gitsigns.stage_buffer, { desc = "Stage buffer" })
					map("n", "<leader>hR", gitsigns.reset_buffer, { desc = "Reset buffer" })
					map("n", "<leader>hp", gitsigns.preview_hunk, { desc = "Preview hunk" })
					map("n", "<leader>hi", gitsigns.preview_hunk_inline, { desc = "Inline preview hunk" })

					map("n", "<leader>hb", function()
						gitsigns.blame_line({ full = true })
					end, { desc = "Blame line (full)" })

					map("n", "<leader>hd", gitsigns.diffthis, { desc = "Diff against index" })

					map("n", "<leader>hD", function()
						gitsigns.diffthis("~")
					end, { desc = "Diff against last commit" })

					map("n", "<leader>hQ", function()
						gitsigns.setqflist("all")
					end, { desc = "Add all hunks to quickfix list" })

					map("n", "<leader>hq", gitsigns.setqflist, { desc = "Add hunks to quickfix list" })

					-- Toggles
					map("n", "<leader>tb", gitsigns.toggle_current_line_blame, { desc = "Toggle line blame" })
					map("n", "<leader>tw", gitsigns.toggle_word_diff, { desc = "Toggle word diff" })

					-- Text object
					map({ "o", "x" }, "ih", gitsigns.select_hunk, { desc = "Select Git hunk" })
				end,
			})
		end,
	},
	{
		"stevearc/oil.nvim",
		---@module 'oil'
		---@type oil.SetupOpts
		opts = {
			columns = {
				"icon",
				"size",
				"mtime",
			},
			delete_to_trash = true,
		},
		-- Optional dependencies
		dependencies = { { "nvim-tree/nvim-web-devicons", opts = {} } },
		view_options = {
			natural_order = "fast",
			show_hidden = true,
			sort = {
				{ "type", "asc" },
				{ "name", "asc" },
			},
		},
		keys = {
			{
				"-",
				function()
					require("oil").open_float(nil, {
						preview = {
							vertical = true, -- For vertical split preview
							-- horizontal = true, -- For horizontal split preview
							-- split = "belowright" -- Control the split position
						},
					})
				end,
				desc = "Open oil in floating window with vertical preview",
				mode = "n",
			},
			{
				"<leader>-",
				function()
					require("oil").open(nil, {})
				end,
				desc = "Open oil",
				mode = "n",
			},
		},
		-- dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if you prefer nvim-web-devicons
		-- Lazy loading is not recommended because it is very tricky to make it work correctly in all situations.
		lazy = false,
	},

	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			preset = "helix",
			defaults = {},
		},
		keys = vim.g.have_nerd_font and {} or {
			{
				"<leader>?",
				function()
					require("which-key").show({ global = false })
				end,
				desc = "Buffer Local Keymaps (which-key)",
			},
		},
	},
	{
		"kevinhwang91/nvim-ufo",
		lazy = false,
		event = "BufRead",
		keys = {
			{
				"K",
				function()
					local winid = require("ufo").peekFoldedLinesUnderCursor()
					if not winid then
						vim.lsp.buf.hover()
					end
				end,
			},
		},
		dependencies = {
			{ "kevinhwang91/promise-async" },
		},
		config = function()
			-- Fold options
			vim.o.fillchars = [[eob: ,fold: ,foldopen:▼,foldsep: ,foldclose:▶]]
			vim.o.foldcolumn = "0" -- '0' is not bad
			vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
			vim.o.foldlevelstart = 99
			vim.o.foldenable = true
			local handler = function(virtText, lnum, endLnum, width, truncate)
				local newVirtText = {}
				local suffix = (" 󰁂 %d "):format(endLnum - lnum)
				local sufWidth = vim.fn.strdisplaywidth(suffix)
				local targetWidth = width - sufWidth
				local curWidth = 0
				for _, chunk in ipairs(virtText) do
					local chunkText = chunk[1]
					local chunkWidth = vim.fn.strdisplaywidth(chunkText)
					if targetWidth > curWidth + chunkWidth then
						table.insert(newVirtText, chunk)
					else
						chunkText = truncate(chunkText, targetWidth - curWidth)
						local hlGroup = chunk[2]
						table.insert(newVirtText, { chunkText, hlGroup })
						chunkWidth = vim.fn.strdisplaywidth(chunkText)
						if curWidth + chunkWidth < targetWidth then
							suffix = suffix .. (" "):rep(targetWidth - curWidth - chunkWidth)
						end
						break
					end
					curWidth = curWidth + chunkWidth
				end
				table.insert(newVirtText, { suffix, "MoreMsg" })
				return newVirtText
			end
			-- vim.deprecate = function() end

			require("ufo").setup({
				fold_virt_text_handler = handler,
			})
		end,
	},
	{
		"nvim-lualine/lualine.nvim",
		enabled = true,
		event = "VeryLazy",
		opts = function()
			local fn = vim.fn

			local git_status_cache = {}

			local on_exit_fetch = function(result)
				if result.code == 0 then
					git_status_cache.fetch_success = true
				end
			end

			local function handle_numeric_result(cache_key)
				return function(result)
					if result.code == 0 then
						git_status_cache[cache_key] = tonumber(result.stdout:match("(%d+)")) or 0
					end
				end
			end

			local async_cmd = function(cmd_str, on_exit)
				local cmd = vim.tbl_filter(function(element)
					return element ~= ""
				end, vim.split(cmd_str, " "))

				vim.system(cmd, { text = true }, on_exit)
			end

			local async_git_status_update = function()
				async_cmd("git fetch origin", on_exit_fetch)
				if not git_status_cache.fetch_success then
					return
				end

				async_cmd("git rev-list --count HEAD..@{upstream}", handle_numeric_result("behind_count"))
				async_cmd("git rev-list --count @{upstream}..HEAD", handle_numeric_result("ahead_count"))
			end

			local function get_git_ahead_behind_info()
				async_git_status_update()
				local status = git_status_cache
				if not status then
					return ""
				end

				local msg = ""
				if type(status.ahead_count) == "number" and status.ahead_count > 0 then
					msg = msg .. string.format("↑[%d] ", status.ahead_count)
				end
				if type(status.behind_count) == "number" and status.behind_count > 0 then
					msg = msg .. string.format("↓[%d] ", status.behind_count)
				end
				return msg
			end

			local function spell()
				return vim.o.spell and "[SPELL]" or ""
			end

			local function ime_state()
				if vim.g.is_mac then
					local layout = fn.libcall(vim.g.XkbSwitchLib, "Xkb_Switch_getXkbLayout", "")
					if fn.match(layout, [[\v(Squirrel\.Rime|SCIM.ITABC)]]) ~= -1 then
						return "[CN]"
					end
				end
				return ""
			end

			local function trailing_space()
				if not vim.o.modifiable then
					return ""
				end
				for i = 1, fn.line("$") do
					if fn.match(fn.getline(i), [[\v\s+$]]) ~= -1 then
						return string.format("[%d]trailing", i)
					end
				end
				return ""
			end

			local function mixed_indent()
				if not vim.o.modifiable then
					return ""
				end
				local space_pat, tab_pat = [[\v^ +]], [[\v^\t+]]
				local space_indent, tab_indent = fn.search(space_pat, "nwc"), fn.search(tab_pat, "nwc")
				local mixed = space_indent > 0 and tab_indent > 0
				local mixed_same_line = fn.search([[\v^(\t+ | +\t)]], "nwc")
				if mixed_same_line > 0 then
					return "MI:" .. mixed_same_line
				end
				if mixed then
					return space_indent > tab_indent and "MI:" .. tab_indent or "MI:" .. space_indent
				end
				return ""
			end

			local diff = function()
				local git_status = vim.b.gitsigns_status_dict
				return git_status
					and { added = git_status.added, modified = git_status.changed, removed = git_status.removed }
			end

			local virtual_env = function()
				if vim.bo.filetype ~= "python" then
					return ""
				end
				local conda_env, venv_path = os.getenv("CONDA_DEFAULT_ENV"), os.getenv("VIRTUAL_ENV")
				if venv_path then
					return string.format("  %s (venv)", vim.fn.fnamemodify(venv_path, ":t"))
				elseif conda_env then
					return string.format("  %s (conda)", conda_env)
				end
				return ""
			end

			local get_active_lsp = function()
				local clients = vim.lsp.get_clients({ bufnr = 0 })
				if not next(clients) then
					return "󰜺"
				end
				local buf_ft = vim.api.nvim_get_option_value("filetype", {})
				for _, client in ipairs(clients) do
					if client.config.filetypes and vim.fn.index(client.config.filetypes, buf_ft) ~= -1 then
						return client.name
					end
				end
				return "󰜺"
			end

			return {
				options = {
					icons_enabled = true,
					theme = "auto",
					component_separators = { left = "⏐", right = "⏐" },
					section_separators = "",
					disabled_filetypes = {},
					always_divide_middle = true,
					refresh = { statusline = 200 },
				},
				sections = {
					lualine_a = {
						{
							function()
								local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":t") -- Folder name
								local filename = vim.fn.expand("%:t") -- Current file
								return string.format("%s/%s", cwd, filename) -- "FolderName/filename"
							end,
							symbols = { readonly = "[]" },
						},
					},
					lualine_b = {
						{
							"branch",
							fmt = function(name)
								return string.sub(name, 1, 20)
							end,
							color = { gui = "italic,bold" },
						},
						{ get_git_ahead_behind_info, color = { fg = "#E0C479" } },
						{ "diff", source = diff },
						{ virtual_env, color = { fg = "black", bg = "#F1CA81" } },
					},
					lualine_c = {
						{ "%S", color = { gui = "bold", fg = "cyan" } },
						{ spell, color = { fg = "black", bg = "#a7c080" } },
					},
					lualine_x = {
						{ get_active_lsp, icon = "" },
						{
							"diagnostics",
							sources = { "nvim_diagnostic" },
							symbols = { error = " ", warn = " ", info = " ", hint = " " },
						},
						{ trailing_space, color = "WarningMsg" },
						{ mixed_indent, color = "WarningMsg" },
					},
					lualine_y = {
						{ "encoding", fmt = string.upper },
						{ "fileformat", symbols = { unix = "unix", dos = "win", mac = "mac" } },
						"filetype",
						{ ime_state, color = { fg = "black", bg = "#f46868" } },
					},
					lualine_z = {
						"location",
						-- "progress",
					},
				},
				inactive_sections = {
					lualine_a = {},
					lualine_b = {},
					lualine_c = { "filename" },
					lualine_x = { "location" },
					lualine_y = {},
					lualine_z = {},
				},
				tabline = {},
				extensions = { "quickfix", "fugitive", "nvim-tree" },
			}
		end,
	},
	{
		"stevearc/dressing.nvim",
		event = "VeryLazy",
		opts = {},
	},
	{
		"mikavilpas/yazi.nvim",
		event = "VeryLazy",
		keys = {
			-- 👇 in this section, choose your own keymappings!
			{
				"<leader>n",
				"<cmd>Yazi<cr>",
				desc = "Open yazi at the current file",
			},
			{
				-- Open in the current working directory
				"<leader>cw",
				"<cmd>Yazi cwd<cr>",
				desc = "Open the file manager in nvim's working directory",
			},
			{
				-- NOTE: this requires a version of yazi that includes
				-- https://github.com/sxyazi/yazi/pull/1305 from 2024-07-18
				"<c-up>",
				"<cmd>Yazi toggle<cr>",
				desc = "Resume the last yazi session",
			},
		},
		opts = {
			-- if you want to open yazi instead of netrw, see below for more info
			open_for_directories = false,
			keymaps = {
				show_help = "<f1>",
			},
		},
	},
	{
		-- example: include a flavor
		"BennyOe/onedark.yazi",
		lazy = true,
		build = function(plugin)
			require("yazi.plugin").build_flavor(plugin)
		end,
	},
	{
		"nvzone/showkeys",
		event = "VeryLazy",
		cmd = "ShowkeysToggle",
		opts = {
			timeout = 1,
			maxkeys = 9,
			-- more opts
		},
	},
	{
		"tpope/vim-sleuth",
	},
}
