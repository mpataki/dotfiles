local wezterm = require 'wezterm'

local config = {}

-- config.term = 'wezterm'

config.window_decorations = 'RESIZE'

config.color_scheme = 'Brewer (base16)'

config.colors = {
    background = '#000000'
}

config.window_padding = {
  left = 2,
  right = 2,
  top = 30,
  bottom = 0,
}

config.font = wezterm.font 'Hack Nerd Font Mono'

config.hide_tab_bar_if_only_one_tab = true

config.keys = {
  {
      key = 'O',
      mods = 'CTRL|SHIFT',
      action = wezterm.action_callback(function(window, pane)
          local sel = window:get_selection_text_for_pane(pane)
          wezterm.open_with(sel)
      end),
  },
  {key="Enter", mods="SHIFT", action=wezterm.action{SendString="\x1b\r"}},
  {
      key = 'z',
      mods = 'CTRL|SHIFT|OPT',
      action = wezterm.action.ActivateWindow(0),
  },
  {
      key = 'x',
      mods = 'CTRL|SHIFT|OPT',
      action = wezterm.action.ActivateWindow(1),
  },
}

return config
