return {
    "tpope/vim-fugitive",
    keys = {
      { "<leader>gs", vim.cmd.Git }
    },
    cmd = { "G", "Git", "GlLog" }
}
