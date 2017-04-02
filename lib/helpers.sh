RED="\e[31m"
GREEN="\e[32m"
BLUE="\e[34m"
YELLOW="\e[33m"
WHITE="\e[37m"
NONE="\e[39m"

function print_with_color() {
  color=$1
  string=$2
  printf "$color$string$NONE\n"
}

function link_file() {
  source_file=$1
  destination=$2

  print_with_color $GREEN "linking $source_file to $destination"

  ln -s "$source_file" "$destination"
}

function check_and_link_file() {
  source_file=$1
  destination=$2

  if [[ -e $destination ]]; then
    print_with_color $YELLOW "$destination already exists. Do you want to override it? (yes/no)"
    read yn
    case $yn in
      yes )
        if [ -d "$destination" ]; then
          rm -rf "$destination"
        else
          rm "$destination"
        fi

        link_file "$source_file" "$destination"
        ;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  else
    link_file "$source_file" "$destination"
  fi
}

function git_clone() {
  repo=$1
  dest=$2

  if [ -e "$dest" ]; then
    print_with_color $YELLOW "$dest already present. Do you want to overwrite it? (yes/no)"
    read yn
    case $yn in
      yes )
        rm -rf $dest
        ;;
      * ) print_with_color $GREEN 'skipping...'; return;;
    esac
  fi

  git clone "$repo" "$dest"
}

