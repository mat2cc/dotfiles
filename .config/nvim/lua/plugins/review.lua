return {
    {
        "lewis6991/gitsigns.nvim",
        event = { "BufReadPre", "BufNewFile" },
        opts = {},
    },
    {
        -- Loaded by the review view only; it routes selections to the visible task companion.
        "coder/claudecode.nvim",
        lazy = true,
        opts = { terminal = { provider = "none" } },
    },
}
