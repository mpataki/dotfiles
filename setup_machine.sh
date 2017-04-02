USER_HOME=$1

. lib/helpers.sh

. bash/setup_bash.sh
. git/setup_git.sh
. vim/setup_vim.sh
. gnupg/setup_gnupg.sh
. awesome/setup_awesome.sh

# TODO: install rbenv
# TODO: install wget
# TODO: install pass
# TODO: install chrome
# TODO: install Albert (?)

print_with_color $GREEN "Done."

