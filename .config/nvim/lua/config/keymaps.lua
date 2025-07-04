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

-- Save
key.set({ "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

key.set("n", "dd", function()
	local count = vim.v.count1
	if vim.fn.getline("."):match("^%s*$") then
		vim.cmd('normal! "' .. "_" .. count .. "dd")
	else
		vim.cmd("normal! " .. count .. "dd")
	end
end, { desc = "Delete line (black hole if empty)" }) -- Added description for clarity

key.set("n", "<leader>uw", function()
	vim.o.wrap = not vim.o.wrap
end, { desc = "Toggle line wrap" })

-- Move window
-- key.set("n", "sh", "<C-w>h")
-- key.set("n", "sk", "<C-w>k")
-- key.set("n", "sj", "<C-w>j")
-- key.set("n", "sl", "<C-w>l")
