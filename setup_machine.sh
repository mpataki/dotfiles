#!/bin/bash
. lib/helpers.sh

if ! [[ `which sudo` ]]; then
  echo "sudo needs to be installed for this to work"
  exit 1
fi

. yay/setup_yay.sh
. bash/setup_bash.sh
. git/setup_git.sh
. vim/setup_vim.sh
. tmux/setup_tmux.sh
. gnupg/setup_gnupg.sh
. zsh/setup_zsh.sh
. java/setup_java.sh
. ruby/setup_ruby.sh
. python/setup_python.sh
. docker/setup_docker.sh
. slack/setup_slack.sh
. misc_tools/setup_misc_tools.sh
. keyboard/setup_keyboard.sh
. xfce/setup_xfce.sh
. tablet/setup_tablet.sh
. simple_terminal/setup_simple_terminal.sh
. virtual_keyboard/setup_virtual_keyboard.sh

print_with_color $GREEN "Done."
