#!/bin/bash
. lib/helpers.sh

if ! [[ `which sudo` ]]; then
  echo "sudo needs to be installed for this to work"
  exit 1
fi

# mac
if is_mac; then
  if ! [[ -e `which brew` ]]; then
    print_with_color $YELLOW "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  print_with_color $GREEN 'Updating Homebrew'
  brew update
else # linux
  . yay/setup_yay.sh
  . snap/setup_snap.sh
  #. keyboard/setup_keyboard.sh
  #. tablet/setup_tablet.sh
  . dotnet/setup_dotnet.sh # this can probably be updated for mac also
  . docker/setup_docker.sh
fi

# both
. zsh/setup_zsh.sh
. git/setup_git.sh
. tmux/setup_tmux.sh
. wezterm/setup_wezterm.sh
. nvim/setup_nvim.sh
. rust/setup_rust.sh
. go/setup_go.sh
. java/setup_java.sh
. python/setup_python.sh
. node/setup_node.sh
. misc_tools/setup_misc_tools.sh

print_with_color $GREEN "Done."
