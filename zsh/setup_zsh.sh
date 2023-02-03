. lib/helpers.sh

function write_zshrc() {
  print_with_color $GREEN "writing $HOME/.zshrc"

  echo ". `pwd`/zsh/zshrc" > $HOME/.zshrc
}

function setup_zsh(){
  pacman_sync 'zsh'
  pacman_sync 'zsh-completions'
  yay_sync starship # prompt
  yay_sync tt-hack-nerd

  # oh-my-zshell
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  if [ -e $HOME/.zshrc ]; then
    print_with_color $YELLOW "$HOME/.zshrc already exists. Do you want to override it? (yes/no)"
    read yn
    case $yn in
      yes|Yes|YES|y|Y ) write_zshrc;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  else
    write_zshrc
  fi

  print_with_color $YELLOW 'Do you want to set zsh as the default shell? (yes/no)'
  read yn
  case $yn in
    yes|Yes|YES|y|Y ) chsh -s /bin/zsh;;
    * ) print_with_color $GREEN 'skipping...';;
  esac
}

print_with_color $YELLOW 'Setup zsh? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_zsh;;
  * ) print_with_color $GREEN 'skipping...';;
esac
