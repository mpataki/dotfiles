function setup_vim(){
  pacman_sync gvim
  pacman_sync the_silver_searcher

  print_with_color $YELLOW 'this next one takes 10+ minutes to install..'
  yaourt_sync vim-youcompleteme-git

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

