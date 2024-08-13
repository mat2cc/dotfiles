local wezterm = require 'wezterm'
local config = {}

config.font = wezterm.font 'JetBrains Mono'
config.font_size = 14.5

config.enable_tab_bar = false
config.color_scheme = 'Dracula (Official)'

config.keys = {
    {
        key = 't',
        mods = 'CMD',
        action = wezterm.action.DisableDefaultAssignment
    }
}

return config

