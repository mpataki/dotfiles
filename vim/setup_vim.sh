function setup_vim(){
  pacman_sync vim

  check_and_link_file `pwd`/vim/vimrc $HOME/.vimrc
  check_and_link_file `pwd`/vim/colors $HOME/.vim/colors

  if ! [ -e $HOME/.vim ]; then
    mkdir $HOME/.vim
  fi
}

print_with_color $YELLOW 'Setup Vim? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_vim;;
  * ) print_with_color $GREEN 'skipping...';;
esac

