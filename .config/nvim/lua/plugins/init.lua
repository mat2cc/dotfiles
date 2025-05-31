return {
    "christoomey/vim-tmux-navigator",
    "kyazdani42/nvim-web-devicons",
    -- { "github/copilot.vim", lazy = false },
    {
        "kylechui/nvim-surround",
        version = "*", -- Use for stability; omit to use `main` branch for the latest features
        config = true
    },
    "justinmk/vim-sneak",
    "towolf/vim-helm",
    "joerdav/templ.vim",
    {
        "lukas-reineke/indent-blankline.nvim",
        main = "ibl",
        opts = {
            scope = { enabled = false }
        }
    },
    {
        'numToStr/Comment.nvim',
        opts = {
            -- add any options here
        },
        lazy = false,
    },
    "j-hui/fidget.nvim",
}
