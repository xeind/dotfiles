return {
	{
		"kdheepak/lazygit.nvim",
		event = "VeryLazy",
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
		event = { "BufReadPre", "BufNewFile" },
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
		-- event = "VeryLazy",
		cmd = { "Oil " },
		keys = {
			{
				"-",
				function()
					require("oil").open_float(nil, {
						preview = {
							vertical = true,
							-- horizontal = true,
							-- split = "belowright",
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
		---@module 'oil'
		---@type oil.SetupOpts
		opts = {
			float = {
				preview_split = "auto",
			},
			columns = {
				"icon",
				-- "size",
				"mtime",
			},
			delete_to_trash = true,
			view_options = {
				natural_order = "fast",
				show_hidden = true,
				sort = {
					{ "type", "asc" },
					{ "name", "asc" },
				},
			},
		},
		dependencies = {
			{ "nvim-tree/nvim-web-devicons" },
		},
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
		event = { "BufReadPost", "BufNewFile" },
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
			{
				"zR",
				function()
					require("ufo").openAllFolds()
				end,
				desc = "Open all folds",
			},
			{
				"zM",
				function()
					require("ufo").closeAllFolds()
				end,
				desc = "Close all folds",
			},
			{
				"<leader>zf",
				function()
					if vim.wo.foldlevel == 99 then
						require("ufo").closeAllFolds()
					else
						require("ufo").openAllFolds()
					end
				end,
				desc = "Toggle all folds",
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
				provider_selector = function(bufnr, filetype, buftype)
					return { "treesitter", "indent" }
				end,
				open_fold_hl_timeout = 150,
				close_fold_kinds_for_ft = {},
			})

			-- Ensure fold levels are properly set for all buffers
			vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWinEnter" }, {
				group = vim.api.nvim_create_augroup("ufo_buffer_folds", { clear = true }),
				callback = function(args)
					-- Skip special buffers
					local buftype = vim.bo[args.buf].buftype
					if buftype == "nofile" or buftype == "terminal" or buftype == "prompt" then
						return
					end

					-- Set buffer-local fold options
					vim.wo.foldlevel = 99
					vim.wo.foldenable = true
				end,
			})
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
		enabled = true,
	},
	{
		"dmtrKovalenko/fff.nvim",
		lazy = false,
		enabled = true,
		-- build = "cargo build --release",
		-- or if you are using nixos
		-- build = "nix run .#release",
		build = function()
			require("fff.download").download_or_build_binary()
		end,

		config = function()
			require("fff").setup({
				prompt = " ",
			})
		end,
		opts = {
			-- pass here all the options
		},
		keys = {
			{
				"<localleader>ff",
				function()
					require("fff").find_files()
				end,
				desc = "Open file picker",
			},
			{
				"<localleader>fg",
				function()
					require("fff").find_in_git_root()
				end,
				desc = "Find files in the Git directory",
			},
			{
				"<localleader>rf",
				function()
					require("fff").scan_files()()
				end,
				desc = "Rescan of files in the current directory",
			},
			{
				"<localleader>rg",
				function()
					require("fff").refresh_git_status()()
				end,
				desc = "Refresh Git Status for current file",
			},
		},
	},
	{
		"nvim-tree/nvim-web-devicons",
		lazy = true,
		opts = { default = true },
	},
	{
		"nvim-lualine/lualine.nvim",
		enabled = true,
		event = "VeryLazy",
		opts = function()
			local fn = vim.fn
			local last_git_check = 0
			local git_check_interval = 300 -- 5 minutes (300 seconds)

			-- Path display cache to prevent flickering
			local path_cache = {}
			local function get_cached_path(bufnr)
				local bufname = vim.api.nvim_buf_get_name(bufnr)
				if path_cache[bufnr] and path_cache[bufnr].name == bufname then
					return path_cache[bufnr].display
				end
				return nil
			end

			local function set_cached_path(bufnr, bufname, display)
				path_cache[bufnr] = { name = bufname, display = display }
			end

			-- Clear cache when buffer is deleted
			vim.api.nvim_create_autocmd("BufDelete", {
				callback = function(ev)
					path_cache[ev.buf] = nil
				end,
			})

			-- Git status cache
			local git_cache = { 
				ahead_count = 0, 
				behind_count = 0, 
				added = 0, 
				changed = 0, 
				removed = 0,
				branch = "",
			}
			local last_git_check = 0
			local git_check_interval = 300 -- 5 minutes (300 seconds)

			local function update_git_cache()
				-- Update ahead/behind
				local ahead_cmd = vim.system(
					{ "git", "rev-list", "--count", "HEAD..@{upstream}" },
					{ text = true },
					function(result)
						if result.code == 0 then
							git_cache.behind_count = tonumber(result.stdout:match("(%d+)")) or 0
						end
					end
				)
				
				local behind_cmd = vim.system(
					{ "git", "rev-list", "--count", "@{upstream}..HEAD" },
					{ text = true },
					function(result)
						if result.code == 0 then
							git_cache.ahead_count = tonumber(result.stdout:match("(%d+)")) or 0
						end
					end
				)

				-- Update diff stats from gitsigns
				local git_status = vim.b.gitsigns_status_dict
				if git_status then
					git_cache.added = git_status.added or 0
					git_cache.changed = git_status.changed or 0
					git_cache.removed = git_status.removed or 0
				end
			end

			local function get_git_combined()
				local now = os.time()
				if now - last_git_check > git_check_interval then
					last_git_check = now
					update_git_cache()
				end

				-- Get branch name
				local branch = vim.b.gitsigns_status_dict and vim.b.gitsigns_status_dict.head or ""
				if branch == "" then
					return ""
				end
				
				-- Truncate branch name
				branch = string.sub(branch, 1, 20)
				
				-- Build status string
				local parts = { "󰘬 " .. branch }
				
				-- Add ahead/behind if non-zero
				if git_cache.ahead_count > 0 or git_cache.behind_count > 0 then
					local sync_info = ""
					if git_cache.ahead_count > 0 then
						sync_info = sync_info .. string.format("↑%d", git_cache.ahead_count)
					end
					if git_cache.behind_count > 0 then
						sync_info = sync_info .. string.format("↓%d", git_cache.behind_count)
					end
					table.insert(parts, sync_info)
				end
				
				-- Add diff stats if dirty
				local has_changes = git_cache.added > 0 or git_cache.changed > 0 or git_cache.removed > 0
				if has_changes then
					local diff_str = ""
					if git_cache.added > 0 then
						diff_str = diff_str .. string.format("+%d", git_cache.added)
					end
					if git_cache.changed > 0 then
						diff_str = diff_str .. string.format("~%d", git_cache.changed)
					end
					if git_cache.removed > 0 then
						diff_str = diff_str .. string.format("-%d", git_cache.removed)
					end
					table.insert(parts, diff_str)
				end
				
				return table.concat(parts, " ")
			end

			-- Autocmd to update git cache on relevant events
			vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
				callback = function()
					update_git_cache()
				end,
			})

			-- Cache for buffer checks
			local trailing_cache, mixed_cache = "", ""
			local last_indent_check = 0
			local indent_check_throttle = 1000 -- 1 second throttle

			local function update_indent_caches()
				local now = vim.loop.now()
				if now - last_indent_check < indent_check_throttle then
					return
				end
				last_indent_check = now

				if not vim.o.modifiable then
					trailing_cache, mixed_cache = "", ""
					return
				end
				
				-- Check trailing spaces
				for i = 1, fn.line("$") do
					if fn.match(fn.getline(i), [[\v\s+$]]) ~= -1 then
						trailing_cache = string.format("%d~", i)
						break
					end
				end
				if trailing_cache == "" then
					-- Check again to make sure we didn't miss anything
					trailing_cache = ""
				end

				-- Check mixed indent
				local space_pat, tab_pat = [[\v^ +]], [[\v^\t+]]
				local space_indent, tab_indent = fn.search(space_pat, "nwc"), fn.search(tab_pat, "nwc")
				local mixed_same_line = fn.search([[\v^(\t+ | +\t)]], "nwc")
				if mixed_same_line > 0 then
					mixed_cache = "MI:" .. mixed_same_line
				elseif space_indent > 0 and tab_indent > 0 then
					mixed_cache = space_indent > tab_indent and "MI:" .. tab_indent or "MI:" .. space_indent
				else
					mixed_cache = ""
				end
			end

			-- Throttled autocmd for indent checks (only on save, not every keystroke)
			vim.api.nvim_create_autocmd({ "BufWritePost" }, {
				callback = function()
					update_indent_caches()
				end,
			})

			local diff = function()
				local git_status = vim.b.gitsigns_status_dict
				return git_status
					and {
						added = git_status.added,
						modified = git_status.changed,
						removed = git_status.removed,
					}
			end

			local virtual_env = function()
				if vim.bo.filetype ~= "python" then
					return ""
				end
				local conda_env, venv_path = os.getenv("CONDA_DEFAULT_ENV"), os.getenv("VIRTUAL_ENV")
				if venv_path then
					return string.format("  %s (venv)", fn.fnamemodify(venv_path, ":t"))
				elseif conda_env then
					return string.format("  %s (conda)", conda_env)
				end
				return ""
			end

			-- Git blame cache and variables
			local blame_cache = {}
			local last_blame_line = {}
			local blame_debounce_timer = nil
			local BLAME_DELAY = 1000 -- 1000ms delay (1 second)
			local BLAME_CACHE_SIZE = 50 -- LRU cache size per buffer

			-- Calculate relative time
			local function format_relative_time(timestamp)
				local now = os.time()
				local diff = now - timestamp
				
				if diff < 60 then
					return "now"
				elseif diff < 3600 then
					return string.format("%dm", math.floor(diff / 60))
				elseif diff < 86400 then
					return string.format("%dh", math.floor(diff / 3600))
				elseif diff < 604800 then
					return string.format("%dd", math.floor(diff / 86400))
				elseif diff < 2592000 then
					return string.format("%dw", math.floor(diff / 604800))
				elseif diff < 31536000 then
					return string.format("%dmo", math.floor(diff / 2592000))
				else
					return string.format("%dy", math.floor(diff / 31536000))
				end
			end

			-- Get color based on recency
			local function get_blame_color(timestamp)
				local now = os.time()
				local diff = now - timestamp
				
				if diff < 86400 then -- < 1 day
					return { fg = "#FFD700" } -- Gold
				elseif diff < 604800 then -- < 1 week
					return { fg = "#A0A0A0" } -- Light gray
				elseif diff < 2592000 then -- < 1 month
					return { fg = "#707070" } -- Medium gray
				else
					return { fg = "#505050" } -- Dark gray
				end
			end

			-- Extract initials from author name
			local function get_initials(author)
				if not author or author == "" then
					return "??"
				end
				
				-- Split by spaces
				local parts = {}
				for part in author:gmatch("%S+") do
					table.insert(parts, part)
				end
				
				if #parts == 1 then
					-- Single name: take first 2 chars or just first char
					return string.upper(string.sub(parts[1], 1, 2))
				else
					-- Multiple names: first letter of first + first letter of last
					return string.upper(string.sub(parts[1], 1, 1) .. string.sub(parts[#parts], 1, 1))
				end
			end

			-- Update blame for current line
			local function update_blame()
				-- Only in normal mode
				if vim.fn.mode() ~= "n" then
					return
				end
				
				local bufnr = vim.api.nvim_get_current_buf()
				local line = vim.api.nvim_win_get_cursor(0)[1]
				
				-- Check if already cached for this line
				if blame_cache[bufnr] and blame_cache[bufnr][line] then
					return
				end
				
				-- Check if this is a git repo
				if not vim.b.gitsigns_status_dict then
					return
				end
				
				local filepath = vim.api.nvim_buf_get_name(bufnr)
				if filepath == "" then
					return
				end
				
				-- Run git blame async
				vim.system(
					{ "git", "blame", "-L", string.format("%d,%d", line, line), "--porcelain", filepath },
					{ text = true },
					function(result)
						if result.code ~= 0 then
							return
						end
						
						local output = result.stdout
						local author = output:match("author (.-)\n") or "Unknown"
						
						-- Skip uncommitted/staged lines ("Not Committed Yet" or empty hash)
						if author == "Not Committed Yet" or output:match("^0{40}") then
							return
						end
						
						local timestamp = tonumber(output:match("author%-time (%d+)")) or os.time()
						
						local initials = get_initials(author)
						local time_str = format_relative_time(timestamp)
						local color = get_blame_color(timestamp)
						
						-- Initialize cache for buffer if needed
						if not blame_cache[bufnr] then
							blame_cache[bufnr] = {}
						end
						
						-- LRU cache management
						local cache = blame_cache[bufnr]
						local cache_count = 0
						for _ in pairs(cache) do
							cache_count = cache_count + 1
						end
						
						-- Remove oldest if cache is full
						if cache_count >= BLAME_CACHE_SIZE then
							local oldest_line = nil
							local oldest_time = math.huge
							for l, data in pairs(cache) do
								if data.cached_at and data.cached_at < oldest_time then
									oldest_time = data.cached_at
									oldest_line = l
								end
							end
							if oldest_line then
								cache[oldest_line] = nil
							end
						end
						
						-- Store with timestamp for LRU
						cache[line] = {
							text = initials .. " " .. time_str,
							color = color,
							cached_at = os.time(),
						}
						
						-- Force lualine refresh
						vim.schedule(function()
							vim.cmd("redrawstatus")
						end)
					end
				)
			end

			-- Debounced blame update
			local function debounced_blame_update()
				-- Cancel existing timer
				if blame_debounce_timer then
					blame_debounce_timer:stop()
					blame_debounce_timer = nil
				end
				
				-- Set new timer
				blame_debounce_timer = vim.defer_fn(function()
					update_blame()
				end, BLAME_DELAY)
			end

			-- Autocmds for blame updates
			local blame_augroup = vim.api.nvim_create_augroup("LualineGitBlame", { clear = true })
			
			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				group = blame_augroup,
				callback = function()
					local bufnr = vim.api.nvim_get_current_buf()
					local line = vim.api.nvim_win_get_cursor(0)[1]
					
					-- Only update if line changed
					if last_blame_line[bufnr] ~= line then
						last_blame_line[bufnr] = line
						debounced_blame_update()
					end
				end,
			})

			vim.api.nvim_create_autocmd({ "BufDelete" }, {
				group = blame_augroup,
				callback = function(args)
					blame_cache[args.buf] = nil
					last_blame_line[args.buf] = nil
				end,
			})

			vim.api.nvim_create_autocmd({ "BufWritePost" }, {
				group = blame_augroup,
				callback = function(args)
					-- Clear cache on save (commit info might change)
					blame_cache[args.buf] = nil
					debounced_blame_update()
				end,
			})

			-- Get blame text for lualine
			local function get_blame_text()
				local bufnr = vim.api.nvim_get_current_buf()
				local line = vim.api.nvim_win_get_cursor(0)[1]
				
				if blame_cache[bufnr] and blame_cache[bufnr][line] then
					return blame_cache[bufnr][line].text
				end
				
				return ""
			end

			-- Get blame color for lualine
			local function get_blame_color_for_lualine()
				local bufnr = vim.api.nvim_get_current_buf()
				local line = vim.api.nvim_win_get_cursor(0)[1]
				
				if blame_cache[bufnr] and blame_cache[bufnr][line] then
					return blame_cache[bufnr][line].color
				end
				
				return { fg = "#808080" } -- Default gray
			end

			local get_active_lsp = function()
				local clients = vim.lsp.get_clients({ bufnr = 0 })
				if not next(clients) then
					return "󰜺"
				end
				local buf_ft = vim.api.nvim_get_option_value("filetype", {})
				for _, client in ipairs(clients) do
					if client.config.filetypes and fn.index(client.config.filetypes, buf_ft) ~= -1 then
						return client.name
					end
				end
				return "󰜺"
			end

			local monotone_theme = {
				normal = {
					a = { bg = "#4B4B4B", fg = "#FFFFFF", gui = "bold" },
					b = { bg = "#2E2E2E", fg = "#C0C0C0" },
					c = { bg = "NONE", fg = "#A0A0A0" },
				},
				insert = {
					a = { bg = "#AFAFAF", fg = "#1E1E1E", gui = "bold" },
					b = { bg = "#C0C0C0", fg = "#2E2E2E" },
					c = { bg = "NONE", fg = "#A0A0A0" },
				},
				visual = {
					a = { bg = "#7F7F7F", fg = "#1E1E1E", gui = "bold" },
					b = { bg = "#4B4B4B", fg = "#FFFFFF" },
					c = { bg = "NONE", fg = "#C0C0C0" },
				},
				replace = {
					a = { bg = "#2E2E2E", fg = "#FF8888", gui = "bold" },
					b = { bg = "#1E1E1E", fg = "#FFAAAA" },
					c = { bg = "NONE", fg = "#FFCCCC" },
				},
				command = {
					a = { bg = "#C0C0C0", fg = "#1E1E1E", gui = "bold" },
					b = { bg = "#808080", fg = "#1E1E1E" },
					c = { bg = "NONE", fg = "#A0A0A0" },
				},
				inactive = {
					a = { bg = "NONE", fg = "#808080", gui = "bold" },
					b = { bg = "NONE", fg = "#606060" },
					c = { bg = "NONE", fg = "#505050" },
				},
			}

			return {
				options = {
					globalstatus = true,
					icons_enabled = true,
					theme = monotone_theme,
					component_separators = { left = "⏐", right = "⏐" },
					section_separators = "",
					always_divide_middle = true,
					refresh = {
						statusline = 200, -- Reduced from 1000ms to 200ms but with caching
						tabline = 200,
						winbar = 200,
					},
				},
				sections = {
					lualine_a = {
						{
							function()
								local bufnr = vim.api.nvim_get_current_buf()
								if not vim.api.nvim_buf_is_valid(bufnr) then
									return ""
								end

								local bufname = vim.api.nvim_buf_get_name(bufnr)

								-- Check cache first to reduce flickering
								local cached = get_cached_path(bufnr)
								if cached then
									return cached
								end

								local display

								-- Handle empty buffer names
								if bufname == "" then
									display = "[No Name]"
									set_cached_path(bufnr, bufname, display)
									return display
								end

								-- Handle Oil.nvim buffers
								if bufname:match("^oil://") then
									local path = bufname:gsub("^oil://", "")
									local relative_path = vim.fn.fnamemodify(path, ":~:.")

									-- Handle root directory or empty path
									if relative_path == "" or relative_path == "." or relative_path == "/" then
										display = "󰉓 ."
										set_cached_path(bufnr, bufname, display)
										return display
									end

									local parts = {}
									for part in relative_path:gmatch("[^/]+") do
										table.insert(parts, part)
									end

									if #parts == 0 then
										display = "󰉓 ."
									elseif #parts <= 2 then
										display = "󰉓 " .. relative_path
									else
										-- Smart truncation for oil paths
										local truncated = parts[1]:sub(1, 1)
										for i = 2, #parts - 1 do
											truncated = truncated .. "/" .. parts[i]:sub(1, 1)
										end
										truncated = truncated .. "/" .. parts[#parts]
										display = "󰉓 " .. truncated
									end

									set_cached_path(bufnr, bufname, display)
									return display
								end

								-- For normal files, use your existing logic
								local relative_path = vim.fn.expand("%:p:.")
								if relative_path == "" then
									display = "[No Name]"
									set_cached_path(bufnr, bufname, display)
									return display
								end

								local parts = {}

								for part in relative_path:gmatch("[^/]+") do
									table.insert(parts, part)
								end

								if #parts == 0 then
									display = relative_path
								elseif #parts <= 3 then
									display = table.concat(parts, "/")
								else
									local dir_abbr = {
										routes = "r",
										handlers = "h",
										components = "c",
										utils = "u",
										src = "src",
										dist = "dist",
										lib = "lib",
										app = "app",
										pages = "p",
										types = "t",
										hooks = "h",
										middleware = "mw",
									}

									local display_parts = {}

									-- Project initial
									display_parts[1] = parts[1]:sub(1, 1)

									-- Special handling for common second-level directories
									if #parts >= 2 then
										local second_dir = parts[2]:lower()
										if second_dir == "src" or second_dir == "dist" or second_dir == "lib" then
											display_parts[2] = second_dir
										else
											display_parts[2] = dir_abbr[second_dir] or second_dir:sub(1, 1)
										end
									end

									-- Middle directories as initials
									for i = 3, #parts - 2 do
										local dir = parts[i]:lower()
										display_parts[i] = dir_abbr[dir] or dir:sub(1, 1)
									end

									-- Last 2 parts full
									display_parts[#parts - 1] = parts[#parts - 1]
									display_parts[#parts] = parts[#parts]

									display = table.concat(display_parts, "/")
								end

								set_cached_path(bufnr, bufname, display)
								return display
							end,
							cond = function()
								local bufnr = vim.api.nvim_get_current_buf()
								return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) ~= ""
							end,
						},
					},
					lualine_b = {
						{ 
							get_git_combined, 
							color = { gui = "italic,bold" },
						},
						{ virtual_env, color = { fg = "black", bg = "#F1CA81" } },
					},
					lualine_c = {
						{
							function()
								return get_blame_text()
							end,
							color = function()
								return get_blame_color_for_lualine()
							end,
							cond = function()
								-- Only show in normal mode and in git repos
								return vim.fn.mode() == "n" and vim.b.gitsigns_status_dict ~= nil
							end,
						},
					},
				lualine_x = {
					-- { get_active_lsp },
					{ "diagnostics", sources = { "nvim_diagnostic" } },
					{
						function()
							if vim.b.treesitter_available == false then
								return "󰁪 " -- Alert circle icon for missing parser
							end
							return ""
						end,
						color = { fg = "#FF6B6B" }, -- Red color for visibility
					},
					-- {
					-- 	function()
					-- 		return trailing_cache
					-- 	end,
					-- 	color = "WarningMsg",
					-- },
						{
							function()
								return mixed_cache
							end,
							color = "WarningMsg",
						},
					},
					lualine_y = {
						{
							"filetype",
							fmt = function(ft)
								return ({
									typescriptreact = "tsx",
									javascriptreact = "jsx",
									typescript = "ts",
									javascript = "js",
									python = "py",
									markdown = "md",
									json = "json",
									lua = "lua",
								})[ft] or ft
							end,
						},
					},
					lualine_z = { "location" },
				},
				extensions = { "quickfix", "fugitive", "nvim-tree" },
			}
		end,
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		event = { "BufReadPost", "BufNewFile" },
		---@module "ibl"
		---@type ibl.config
		opts = {},
		config = function()
			require("ibl").setup({
				indent = { char = "▏" },
				whitespace = { highlight = { "Whitespace" } },
				scope = {
					show_start = false,
					show_end = false,
				},
			})
		end,
	},
}
