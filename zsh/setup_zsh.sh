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
  git_clone https://github.com/romkatv/powerlevel10k.git $HOME/.oh-my-zsh/themes/powerlevel10k

  wget https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf
  wget https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf
  wget https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf
  wget https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf

  mkdir -p ~/.local/share/fonts
  mv 'MesloLGS NF Regular.ttf' ~/.local/share/fonts/
  mv 'MesloLGS NF Bold.ttf' ~/.local/share/fonts/
  mv 'MesloLGS NF Italic.ttf' ~/.local/share/fonts/
  mv 'MesloLGS NF Bold Italic.ttf' ~/.local/share/fonts/

  fc-cache -vf ~/.local/share/fonts/

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
