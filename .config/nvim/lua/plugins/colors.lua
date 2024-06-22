return {
    { "catppuccin/nvim",            name = "catppuccin", lazy = true },
    { "morhetz/gruvbox",            lazy = true },
    { "Shatur/neovim-ayu",          lazy = true },
    { "folke/tokyonight.nvim",      lazy = true },
    { "rebelot/kanagawa.nvim",      lazy = true,
        opts = {
            colors = {
                palette = {
                    samuraiRed = "#D93F41",
                }
            }
        }
    },
    {
        'rose-pine/neovim',
        name = 'rose-pine',
        lazy = true,
        opts = { dark_variant = 'moon' } -- moon | main
    },
}

-- catppuccin-latte, catppuccin-frappe, catppuccin-macchiato, catppuccin-mocha, catppuccin
-- tokyonight-moon, tokyonight-night, tokyonight-storm, tokyonight-day
