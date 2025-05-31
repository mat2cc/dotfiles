return {
    "tpope/vim-fugitive",
    keys = {
      { "<leader>gs", vim.cmd.Git },
      { "<leader>gv", ":vertical G<CR>"}
    },
    cmd = { "G", "Git", "GlLog" }
}
