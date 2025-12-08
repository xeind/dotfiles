local api = vim.api
local key = vim.keymap

local function augroup(name)
	return vim.api.nvim_create_augroup("xd_" .. name, { clear = true })
end

-- Highlight yank using IncSearch
api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight yanked text",
	group = augroup("highlight_yank"),
	callback = function()
		vim.highlight.on_yank({
			higroup = "IncSearch",
			timeout = 60,
		})
	end,
})

-- Removes whitespaces on save (with exclusions)
api.nvim_create_autocmd("BufWritePre", {
	desc = "Remove trailing whitespace on save",
	group = augroup("trim_whitespace"),
	callback = function()
		-- Skip for certain filetypes where trailing whitespace matters
		local excluded_fts = { "markdown", "diff", "patch" }
		if vim.tbl_contains(excluded_fts, vim.bo.filetype) then
			return
		end
		local save_cursor = vim.fn.getpos(".")
		vim.cmd([[%s/\s+$//e]])
		vim.fn.setpos(".", save_cursor)
	end,
})

-- Keep the cursor position when yanking
local cursorPreYank

key.set({ "n", "x" }, "y", function()
	cursorPreYank = api.nvim_win_get_cursor(0)
	return "y"
end, { expr = true })

key.set("n", "Y", function()
	cursorPreYank = api.nvim_win_get_cursor(0)
	return "yg_"
end, { expr = true })

api.nvim_create_autocmd("TextYankPost", {
	desc = "Restore cursor position after yank",
	group = augroup("restore_cursor_after_yank"),
	callback = function()
		if vim.v.event.operator == "y" and cursorPreYank then
			api.nvim_win_set_cursor(0, cursorPreYank)
		end
	end,
})

-- Yankring: shift numbered registers on yank
api.nvim_create_autocmd("TextYankPost", {
	desc = "Shift numbered registers on yank",
	group = augroup("yankring"),
	callback = function()
		if vim.v.event.operator == "y" then
			for i = 9, 1, -1 do
				vim.fn.setreg(tostring(i), vim.fn.getreg(tostring(i - 1)))
			end
		end
	end,
})

-- Restore cursor to file position in previous editing session
api.nvim_create_autocmd("BufReadPost", {
	desc = "Restore cursor to last position",
	group = augroup("restore_last_position"),
	callback = function(args)
		local mark = api.nvim_buf_get_mark(args.buf, '"')
		local line_count = api.nvim_buf_line_count(args.buf)
		if mark[1] > 0 and mark[1] <= line_count then
			vim.cmd('normal! g`"zz')
		end
	end,
})

-- Show cursorline only in active window
api.nvim_create_autocmd({ "WinEnter", "BufEnter", "InsertLeave" }, {
	desc = "Enable cursorline in active window",
	group = augroup("cursorline_active"),
	callback = function()
		vim.opt_local.cursorline = true
	end,
})

api.nvim_create_autocmd({ "WinLeave", "BufLeave", "InsertEnter" }, {
	desc = "Disable cursorline in inactive window",
	group = augroup("cursorline_inactive"),
	callback = function()
		vim.opt_local.cursorline = false
	end,
})

-- Check if we need to reload the file when it changed
api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
	desc = "Check if buffer needs reloading",
	group = augroup("checktime"),
	callback = function()
		if vim.o.buftype ~= "nofile" then
			vim.cmd("checktime")
		end
	end,
})

-- Wrap and check for spell in text filetypes
api.nvim_create_autocmd("FileType", {
	desc = "Enable wrap and spell for text filetypes",
	group = augroup("wrap_spell"),
	pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
	end,
})

-- IDE-like highlight references under cursor using LSP (with debouncing)
local lsp_debounce_timer = nil
local lsp_debounce_delay = 100 -- milliseconds

api.nvim_create_autocmd("CursorMoved", {
	desc = "Highlight LSP references under cursor (debounced)",
	group = augroup("lsp_reference_highlight"),
	callback = function()
		-- Cancel previous timer if it exists
		if lsp_debounce_timer then
			vim.fn.timer_stop(lsp_debounce_timer)
		end

		-- Set new timer
		lsp_debounce_timer = vim.fn.timer_start(lsp_debounce_delay, function()
			if vim.fn.mode() ~= "i" then
				local clients = vim.lsp.get_clients({ bufnr = 0 })
				local supports_highlight = false
				for _, client in ipairs(clients) do
					if client.server_capabilities.documentHighlightProvider then
						supports_highlight = true
						break
					end
				end

				if supports_highlight then
					vim.lsp.buf.clear_references()
					vim.lsp.buf.document_highlight()
				end
			end
		end)
	end,
})

api.nvim_create_autocmd("CursorMovedI", {
	desc = "Clear LSP highlights in insert mode",
	group = augroup("lsp_reference_highlight"),
	callback = function()
		vim.lsp.buf.clear_references()
	end,
})

-- Open help in vertical split
api.nvim_create_autocmd("FileType", {
	desc = "Open help in vertical split",
	group = augroup("vertical_help"),
	pattern = "help",
	command = "wincmd L",
})

-- No auto continue comments on new line
api.nvim_create_autocmd("FileType", {
	desc = "Disable auto-commenting on new line",
	group = augroup("no_auto_comment"),
	callback = function()
		vim.opt_local.formatoptions:remove({ "c", "r", "o" })
	end,
})

-- Syntax highlighting for dotenv files
api.nvim_create_autocmd("BufRead", {
	desc = "Set filetype for .env files",
	group = augroup("dotenv_ft"),
	pattern = { ".env", ".env.*" },
	callback = function()
		vim.bo.filetype = "dosini"
	end,
})

-- Re-apply highlights when colorscheme loads
api.nvim_create_autocmd("ColorScheme", {
	desc = "Apply custom highlights on colorscheme load",
	group = augroup("custom_highlights"),
	callback = function()
		-- Visual selection: Same as CursorLine
		api.nvim_set_hl(0, "Visual", {
			bg = "#363636", -- Same as CursorLine
		})

		-- LSP reference highlights (lighter with subtle tint)
		api.nvim_set_hl(0, "LspReferenceText", {
			bg = "#3a3a45", -- Lighter with subtle blue tint
		})
		api.nvim_set_hl(0, "LspReferenceRead", {
			bg = "#3a3a45",
		})
		api.nvim_set_hl(0, "LspReferenceWrite", {
			bg = "#3d3a45", -- Slightly different tint for writes
		})
	end,
})

-- Apply highlights immediately on startup
vim.schedule(function()
	api.nvim_set_hl(0, "Visual", {
		bg = "#363636",
	})
	api.nvim_set_hl(0, "LspReferenceText", {
		bg = "#3a3a45",
	})
	api.nvim_set_hl(0, "LspReferenceRead", {
		bg = "#3a3a45",
	})
	api.nvim_set_hl(0, "LspReferenceWrite", {
		bg = "#3d3a45",
	})
end)

-- Format on save
-- api.nvim_create_autocmd("BufWritePre", {
-- 	group = augroup("autoformat"),
-- 	pattern = "*",
-- 	callback = function(args)
-- 		require("conform").format({ bufnr = args.buf })
-- 	end,
-- })

-- Auto-rescan fff.nvim when Oil.nvim saves files
api.nvim_create_autocmd("BufWritePost", {
	desc = "Auto-rescan fff when Oil saves files",
	group = augroup("fff_oil_integration"),
	pattern = "oil://*",
	callback = function()
		-- Schedule to avoid blocking Oil's save operation
		vim.schedule(function()
			-- Small delay to ensure Oil finishes filesystem operations
			vim.defer_fn(function()
				-- Only trigger if fff is initialized
				local ok, fuzzy = pcall(require, "fff.fuzzy")
				if ok then
					-- Trigger rescan (pcall to avoid errors if scan fails)
					local scan_ok, err = pcall(fuzzy.scan_files)
					if not scan_ok then
						vim.notify("fff rescan failed: " .. tostring(err), vim.log.levels.WARN)
					end
				end
			end, 100) -- 100ms delay for Oil to complete
		end)
	end,
})
