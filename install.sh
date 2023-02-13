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
  . vim/setup_vim.sh # this should be on mac also, but could use some modernization first.
  #. keyboard/setup_keyboard.sh
  #. tablet/setup_tablet.sh
  . dotnet/setup_dotnet.sh # this can probably be updated for mac also
fi

# both
. zsh/setup_zsh.sh
. git/setup_git.sh
. tmux/setup_tmux.sh
. java/setup_java.sh
# . ruby/setup_ruby.sh
. python/setup_python.sh
. docker/setup_docker.sh
. misc_tools/setup_misc_tools.sh

print_with_color $GREEN "Done."