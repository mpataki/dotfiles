local wezterm = require 'wezterm'

local config = {}

config.color_scheme = 'Brogrammer'
config.colors = {
    background = '#000000'
}
config.font = wezterm.font 'Hack Nerd Font Mono'
config.hide_tab_bar_if_only_one_tab = true

return config

