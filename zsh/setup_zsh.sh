. lib/helpers.sh

function write_zshrc() {
  print_with_color $GREEN "writing $HOME/.zshrc"

  echo ". `pwd`/zsh/zshrc" > $HOME/.zshrc
}

function setup_zsh(){
  pacman_sync 'zsh'
  pacman_sync 'zsh-completions'

  # oh-my-zshell
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"


  # theme
  git_clone https://github.com/bhilburn/powerlevel9k.git ~/.oh-my-zsh/custom/themes/powerlevel9k

  wget https://github.com/powerline/powerline/raw/develop/font/PowerlineSymbols.otf
  wget https://github.com/powerline/powerline/raw/develop/font/10-powerline-symbols.conf

  mkdir -p ~/.local/share/fonts
  mv PowerlineSymbols.otf ~/.local/share/fonts/

  fc-cache -vf ~/.local/share/fonts/

  mkdir -p ~/.config/fontconfig/conf.d/
  mv 10-powerline-symbols.conf ~/.config/fontconfig/conf.d/

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
