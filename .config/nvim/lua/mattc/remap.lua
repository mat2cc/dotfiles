vim.g.mapleader = " "
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

vim.keymap.set("i", "jk", "<Esc>")
vim.keymap.set("i", "jK", "<Esc>")
vim.keymap.set("i", "Jk", "<Esc>")
vim.keymap.set("i", "JK", "<Esc>")

vim.keymap.set("i", "<C-j>", "<nop>")
vim.keymap.set("i", "<C-j>", "<nop>")

vim.keymap.set("n", "J", "mzJ`z")

vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- paste in visual without adding to register
vim.keymap.set("x", "<leader>p", "\"_dP")

-- copy to clipboard
vim.keymap.set("n", "<leader>y", "\"+y")
vim.keymap.set("v", "<leader>y", "\"+y")
vim.keymap.set("n", "<leader>Y", "\"+Y")

-- delete lines to blank register
vim.keymap.set("n", "<leader>d", "\"_d")
vim.keymap.set("v", "<leader>d", "\"_d")

vim.keymap.set("n", "Q", "<nop>")

vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux new tmux-sessionizer<CR>")

vim.keymap.set("n", "<leader>n", [[:%s/\<<C-r><C-w>\>//gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

vim.keymap.set("n", "<leader>cj", ":cnext<CR>")
vim.keymap.set("n", "<leader>ck", ":cprev<CR>")
vim.keymap.set("n", "<leader>co", ":copen<CR>")
vim.keymap.set("n", "<leader>cc", ":cclose<CR>")

vim.keymap.set("n", "<leader>fp", ":let @+ = expand('%:p')<CR>"); -- file path
vim.keymap.set("n", "<leader>rfp", ":let @+ = expand('%:.')<CR>"); -- relative file path

vim.keymap.set("i", "<A-BS>", "<C-W>") -- delete word backward

-- using defx instead of netrw
-- vim.keymap.set("n", "ssf", "<cmd>Ex<CR>") 
