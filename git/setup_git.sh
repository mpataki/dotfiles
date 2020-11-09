
function setup_git() {
  pacman_sync git
  pacman_sync hub
  pacman_sync github-cli
  pacman_sync diff-so-fancy

  check_and_link_file `pwd`/git/gitconfig $HOME/.gitconfig
  check_and_link_file `pwd`/git/gitignore $HOME/.gitignore

  # hub completions
  mkdir -p ~/.zsh/completions
  cp /usr/local/share/zsh/site-functions/_hub ~/.zsh/completions/_hub
}

print_with_color $YELLOW 'Setup Git? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_git;;
  * ) print_with_color $GREEN 'skipping...';;
esac

