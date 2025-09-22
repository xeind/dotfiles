-- Core Neovim Configuration Export
-- Excludes VSCode-conflicting plugins (UI, completion, file pickers)
-- Suitable for standalone Neovim usage

-- ============================================================================
-- CORE OPTIONS
-- ============================================================================
local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.wrap = false
opt.cursorline = true
opt.signcolumn = "yes"
opt.showmode = false
opt.winborder = "rounded"

opt.tabstop = 4
-- opt.softtabstop = 4
-- opt.shiftwidth = 4
-- opt.expandtab = true

opt.undofile = true
opt.clipboard = "unnamedplus"
opt.autochdir = false
opt.swapfile = false

opt.listchars = {
	tab = "▏ ",
	trail = "·",
	eol = "¬",
}

opt.list = true
opt.ignorecase = true
opt.smartcase = true

opt.splitright = true
opt.splitbelow = true
opt.scrolloff = 6

vim.cmd([[let &t_Cs = "\e[4:3m"]])
vim.cmd([[let &t_Ce = "\e[4:0m"]])

-- Leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- ============================================================================
-- CORE KEYMAPS
-- ============================================================================
local key = vim.keymap
local opts = { noremap = true, silent = true }

key.set("n", "x", '"_x', { desc = "Disable yank with X" })

-- Tmux cant use C-i
key.set("n", "<A-i>", "<C-i>", { desc = "Jumplist Forward" })
key.set("n", "<A-o>", "<C-o>", { desc = "Jumplist Backward" })

-- Center page when Scrolling
key.set("n", "<C-d>", "<C-d>zz", { desc = "Half Page Down and Center" })
key.set("n", "<C-u>", "<C-u>zz", { desc = "Half Page Up and Center" })

-- Delete word backswards
key.set("n", "dw", 'vb"_d', { desc = "Delete word backwards" })

-- Select all
key.set("n", "<C-a>", "gg<S-v>G", { desc = "Select all" })

-- New tab
key.set("n", "te", ":tabedit")
key.set("n", "<tab>", ":tabnext<Return>", opts)
key.set("n", "<s-tab>", ":tabprev<Return>", opts)

-- Split window
key.set("n", "ss", ":split<Return>", opts)
key.set("n", "sv", ":vsplit<Return>", opts)

-- Resize window
key.set("n", "<C-w><left>", "<C-w><")
key.set("n", "<C-w><right>", "<C-w>>")
key.set("n", "<C-w><up>", "<C-w>+")
key.set("n", "<C-w><down>", "<C-w>-")

-- File operations
key.set("n", "<leader>o", ":update<CR> :source<CR>", { desc = "Source File" })
key.set("n", "<leader>w", ":write<CR>", { desc = "Write File" })
key.set("n", "<leader>q", ":quit<CR>", { desc = "Quit File" })

-- Blackhole delete only for empty lines, otherwise normal delete
vim.keymap.set("n", "dd", function()
	local count = vim.v.count1
	local line_empty = vim.fn.getline("."):match("^%s*$")
	if line_empty then
		-- Use blackhole register for empty lines
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('"_' .. count .. "dd", true, false, true), "n", false)
	else
		-- Normal delete
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(count .. "dd", true, false, true), "n", false)
	end
end, { desc = "Delete line (black hole if empty)", noremap = true, silent = true })

key.set("n", "<leader>uw", function()
	vim.o.wrap = not vim.o.wrap
end, { desc = "Toggle line wrap" })

-- ============================================================================
-- CORE AUTOCOMMANDS
-- ============================================================================
local api = vim.api

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

-- Wrap and check for spell in text filetypes
api.nvim_create_autocmd("FileType", {
	group = augroup("wrap_spell"),
	pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
	end,
})

-- ============================================================================
-- MINIMAL PLUGIN SETUP (Optional - only core functionality)
-- ============================================================================

-- Basic Treesitter setup (if available)
if pcall(require, "nvim-treesitter.configs") then
	require("nvim-treesitter.configs").setup({
		ensure_installed = {
			"c", "lua", "vim", "vimdoc", "query", "elixir", "heex",
			"javascript", "html", "json5", "python", "markdown", "dockerfile",
		},
		auto_install = true,
		sync_install = false,
		highlight = {
			enable = true,
			additional_vim_regex_highlighting = false,
		},
		indent = { enable = true },
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
end

-- Basic LSP setup (if available)
if pcall(require, "lspconfig") then
	-- Simple diagnostic configuration
	vim.diagnostic.config({
		virtual_text = {
			severity = { max = "WARN" },
			source = "if_many",
			spacing = 4,
			prefix = "• ",
		},
		underline = true,
		severity_sort = true,
		float = {
			focusable = true,
			style = "minimal",
			border = "rounded",
			source = "always",
			header = "",
			prefix = "",
		},
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = "",
				[vim.diagnostic.severity.WARN] = "",
				[vim.diagnostic.severity.INFO] = "",
				[vim.diagnostic.severity.HINT] = "",
			},
		},
	})

	-- Basic LSP attach function
	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
		callback = function(event)
			local map = function(keys, func, desc)
				vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
			end

			map("gd", vim.lsp.buf.definition, "[G]oto [D]efinition")
			map("gr", vim.lsp.buf.references, "[G]oto [R]eferences")
			map("gI", vim.lsp.buf.implementation, "[G]oto [I]mplementation")
			map("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
			map("<leader>D", vim.lsp.buf.type_definition, "Type [D]efinition")
			map("<leader>cr", vim.lsp.buf.rename, "[R]e[n]ame")
			map("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")
			map("K", vim.lsp.buf.hover, "Hover Documentation")
			
			-- Diagnostics
			map("<leader>lk", vim.diagnostic.open_float, "Open Diagnostics in Floating Window")
			map("<leader>ln", function()
				vim.diagnostic.jump({ count = 1, float = true })
			end, "Go to next diagnostic")
			map("<leader>lp", function()
				vim.diagnostic.jump({ count = -1, float = true })
			end, "Go to previous diagnostic")
		end,
	})
end

-- ============================================================================
-- VISUAL SETTINGS
-- ============================================================================
vim.cmd([[hi StatusLine guibg=NONE]])
vim.opt.guicursor = ""

-- Set colorscheme if available, fallback to default
pcall(vim.cmd, "colorscheme habamax")

print("Core Neovim configuration loaded successfully!")
