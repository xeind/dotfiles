local key = vim.keymap
local opts = { noremap = true, silent = true }

key.set("n", "x", '"_x', { desc = "Disable yank with X" })

-- Center page when Scrolling
key.set("n", "<C-d>", "<C-d>zz", { desc = "Half Page Down and Center" })
key.set("n", "<C-u>", "<C-u>zz", { desc = "Half Page Up and Center" })

-- Delete word
key.set("n", "dw", 'vb"_d')

-- Select all
key.set("n", "<C-a>", "gg<S-v>G")

-- New tab
key.set("n", "te", ":tabedit")
key.set("n", "<tab>", ":tabnext<Return>", opts)
key.set("n", "<s-tab>", ":tabprev<Return>", opts)

-- Split window
key.set("n", "ss", ":split<Return>", opts)
key.set("n", "sv", ":vsplit<Return>", opts)

-- Move window
key.set("n", "sh", "<C-w>h")
key.set("n", "sk", "<C-w>k")
key.set("n", "sj", "<C-w>j")
key.set("n", "sl", "<C-w>l")

-- Resize window
key.set("n", "<C-w><left>", "<C-w><")
key.set("n", "<C-w><right>", "<C-w>>")
key.set("n", "<C-w><up>", "<C-w>+")
key.set("n", "<C-w><down>", "<C-w>-")

-- Save
key.set({ "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

key.set("n", "gl", function()
	vim.diagnostic.open_float()
end, { desc = "Open Diagnostics in Float" })

-- Don't yank whitespace with dd
key.set("n", "dd", function()
	if vim.fn.getline("."):match("^%s*$") then
		vim.api.nvim_feedkeys('"_dd', "n", false)
	else
		vim.cmd("normal! dd")
	end
end)
