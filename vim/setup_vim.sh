function setup_vim(){
  pacman_sync vim

  check_and_link_file `pwd`/vim/vimrc $USER_HOME/.vimrc

  if ! [ -e ~/.vim ]; then
    mkdir ~/.vim
  fi

  git_clone https://github.com/ctrlpvim/ctrlp.vim.git $USER_HOME/.vim/bundle/ctrlp.vim
}

print_with_color $YELLOW 'Setup Vim? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_vim;;
  * ) print_with_color $GREEN 'skipping...';;
esac

