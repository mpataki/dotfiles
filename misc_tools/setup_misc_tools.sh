
function setup_misc_tools() {
  homebrew_install 'rbenv' 'rbenv'
  homebrew_install 'wget' 'wget'
  homebrew_install 'jq' 'jq'
  homebrew_install 'htop' 'htop'
  homebrew_install 'the_silver_searcher' 'the_silver_searcher'
  homebrew_install 'python' 'python'
}

print_with_color $YELLOW 'Setup misc tools? (yes/no)'
read yn
case $yn in
  yes ) setup_misc_tools;;
  * ) print_with_color $GREEN 'skipping...';;
esac
