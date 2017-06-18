#!/bin/bash
. lib/helpers.sh

if ! [[ `which sudo` ]]; then
  echo "sudo needs to be installed for this to work"
fi

. bash/setup_bash.sh
. git/setup_git.sh
. vim/setup_vim.sh
. gnupg/setup_gnupg.sh
. x/setup_x.sh
. awesome/setup_awesome.sh
. xterm/setup_xterm.sh
. xkb/setup_xkb.sh
. java/setup_java.sh

print_with_color $GREEN "Done."

