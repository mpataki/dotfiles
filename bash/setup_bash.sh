
function write_bash_profile() {
  print_with_color $GREEN "writing $HOME/.bash_profile"
  echo ". `pwd`/bash/bash_profile" > $HOME/.bash_profile
}

function setup_bash(){
  if [ -e $HOME/.bash_profile ]; then
    print_with_color $YELLOW "$HOME/.bash_profile already exists. Do you want to override it? (yes/no)"
    read yn
    case $yn in
      yes ) write_bash_profile;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  else
    write_bash_profile
  fi

  # TODO: install bash-completion (?)
}

print_with_color $YELLOW 'Setup Bash? (yes/no)'
read yn
case $yn in
  yes ) setup_bash;;
  * ) print_with_color $GREEN 'skipping...';;
esac
