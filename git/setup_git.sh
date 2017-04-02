
function setup_git() {
  pacman_sync git
  # TODO: install hub
  # TODO: install diff-so-fancy

  check_and_link_file `pwd`/git/gitconfig $USER_HOME/.gitconfig
  check_and_link_file `pwd`/git/gitignore $USER_HOME/.gitignore
}

print_with_color $YELLOW 'Setup Git? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_git;;
  * ) print_with_color $GREEN 'skipping...';;
esac

