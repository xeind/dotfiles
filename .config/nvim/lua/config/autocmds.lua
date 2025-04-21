local api = vim.api
local key = vim.keymap

local function augroup(name)
	return vim.api.nvim_create_augroup("xd_" .. name, { clear = true })
end

-- Re-apply highlights when colorscheme loads
api.nvim_create_autocmd("ColorScheme", {
	group = augroup("custom_highlights"),
	callback = function()
		api.nvim_set_hl(0, "Search", {
			bg = "#E6C384",
			fg = "#333333",
			italic = true,
		})
		api.nvim_set_hl(0, "IncSearch", {
			bg = "#E6C384",
			fg = "#333333",
			bold = true,
			italic = true,
		})
	end,
})

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

-- Removes whitespaces on save
api.nvim_create_autocmd("BufWritePre", {
	group = augroup("trim_whitespace"),
	callback = function()
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
	group = augroup("restore_cursor_after_yank"),
	callback = function()
		if vim.v.event.operator == "y" and cursorPreYank then
			api.nvim_win_set_cursor(0, cursorPreYank)
		end
	end,
})

-- Restore cursor to file position in previous editing session
api.nvim_create_autocmd("BufReadPost", {
	group = augroup("restore_last_position"),
	callback = function(args)
		local mark = api.nvim_buf_get_mark(args.buf, '"')
		local line_count = api.nvim_buf_line_count(args.buf)
		if mark[1] > 0 and mark[1] <= line_count then
			vim.cmd('normal! g`"zz')
		end
	end,
})

-- Cursorline on active windows
api.nvim_create_autocmd({ "InsertLeave", "WinEnter" }, {
	group = augroup("cursorline_active"),
	callback = function()
		if vim.w.auto_cursorline then
			vim.wo.cursorline = true
			vim.w.auto_cursorline = false
		end
	end,
})

api.nvim_create_autocmd({ "InsertEnter", "WinLeave" }, {
	group = augroup("cursorline_inactive"),
	callback = function()
		if vim.wo.cursorline then
			vim.w.auto_cursorline = true
			vim.wo.cursorline = false
		end
	end,
})

-- Format on save
api.nvim_create_autocmd("BufWritePre", {
	group = augroup("autoformat"),
	pattern = "*",
	callback = function(args)
		require("conform").format({ bufnr = args.buf })
	end,
})

-- Check if we need to reload the file when it changed
api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
	group = augroup("checktime"),
	callback = function()
		if vim.o.buftype ~= "nofile" then
			vim.cmd("checktime")
		end
	end,
})

-- Shift numbered registers up (1 becomes 2, etc.)
local function yank_shift()
	for i = 9, 1, -1 do
		vim.fn.setreg(tostring(i), vim.fn.getreg(tostring(i - 1)))
	end
end

-- Create autocmd for TextYankPost event
api.nvim_create_autocmd("TextYankPost", {
	group = augroup("yank-history"),
	callback = function()
		local event = vim.v.event
		if event.operator == "y" then
			yank_shift()
		end
	end,
})

-- wrap and check for spell in text filetypes
api.nvim_create_autocmd("FileType", {
	group = augroup("wrap_spell"),
	pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
	end,
})
