return {
    "nvim-neorg/neorg",
    version = "*",
    opts = {
        load = {
            ["core.defaults"] = {}, -- Loads default behaviour
            ["core.concealer"] = {}, -- Loads default behaviour
            ["core.dirman"] = { -- Manages Neorg workspaces
                config = {
                    workspaces = {
                        notes = "~/notes",
                    },
                },
            },
        },
    },
    build = ":Neorg sync-parsers",
    dependencies = "nvim-lua/plenary.nvim",
    keys = {
      { "<leader>ne", ":Neorg workspace notes<CR>"}
    },
    priority = 60
}
