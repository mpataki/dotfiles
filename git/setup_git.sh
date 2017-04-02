
function setup_git() {
  # TODO: install git
  # TODO: install bash-completion
  # TODO: install hub
  # TODO: install diff-so-fancy

  check_and_link_file `pwd`/git/gitconfig $HOME/.gitconfig
  check_and_link_file `pwd`/git/gitignore $HOME/.gitignore
}

print_with_color $YELLOW 'Setup Git? (yes/no)'
read yn
case $yn in
  yes ) setup_git;;
  * ) print_with_color $GREEN 'skipping...';;
esac
