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

--
key.set("n", "<leader>o", ":update<CR> :source<CR>", { desc = "Source File" })
key.set("n", "<leader>w", ":write<CR>", { desc = "Write File" })
key.set("n", "<leader>q", ":quit<CR>", { desc = "Quit File" })
-- key.set("n", "<leader>Q", ":quit!<CR>", { desc = "Force Quit File" })

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

-- Move window
-- key.set("n", "sh", "<C-w>h")
-- key.set("n", "sk", "<C-w>k")
-- key.set("n", "sj", "<C-w>j")
-- key.set("n", "sl", "<C-w>l")
