#!/bin/bash
. lib/helpers.sh

# Configure Ruby versions to install
RUBY_VERSIONS=("latest")
DEFAULT_RUBY_VERSION="latest"

# Standard gems to install for each Ruby version
STANDARD_GEMS=(
  "ruby-lsp"
  "rake"
  "debug"
)

function install_gems_for_version() {
  local version=$1
  print_with_color $BLUE "Installing standard gems for Ruby $version"

  # Set the Ruby version temporarily using ASDF_RUBY_VERSION environment variable
  export ASDF_RUBY_VERSION="$version"

  # Bundler is included with Ruby 2.6+, but verify it's available
  if ! gem list bundler -i &> /dev/null; then
    print_with_color $YELLOW 'Installing bundler'
    gem install bundler
  else
    print_with_color $GREEN 'bundler already available'
  fi

  # Install each standard gem
  for gem_name in "${STANDARD_GEMS[@]}"; do
    if ! gem list "$gem_name" -i &> /dev/null; then
      print_with_color $YELLOW "Installing $gem_name"
      gem install "$gem_name"
    else
      print_with_color $GREEN "$gem_name already installed"
    fi
  done

  # Unset the version override
  unset ASDF_RUBY_VERSION

  # Reshim to update shims
  asdf reshim ruby "$version"
}

function setup_ruby() {
  print_with_color $GREEN 'Setting up asdf for Ruby development'

  if is_mac; then
    if ! [[ `which asdf` ]]; then
      print_with_color $YELLOW 'Installing asdf via Homebrew'
      brew install asdf
    else
      print_with_color $GREEN 'asdf already installed'
    fi
  else
    if [ ! -d "$HOME/.asdf" ]; then
      print_with_color $YELLOW 'Installing asdf via git'
      git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
    else
      print_with_color $GREEN 'asdf already installed'
    fi
  fi

  # Source asdf for this script session
  if is_mac; then
    if [ -f /opt/homebrew/opt/asdf/libexec/asdf.sh ]; then
      . /opt/homebrew/opt/asdf/libexec/asdf.sh
    fi
  else
    if [ -f "$HOME/.asdf/asdf.sh" ]; then
      . "$HOME/.asdf/asdf.sh"
    fi
  fi

  # Install Ruby plugin
  if ! asdf plugin list | grep -q ruby; then
    print_with_color $YELLOW 'Installing asdf Ruby plugin'
    asdf plugin add ruby https://github.com/asdf-vm/asdf-ruby.git
  else
    print_with_color $GREEN 'asdf Ruby plugin already installed'
  fi

  # Resolve "latest" version if needed
  local resolved_versions=()
  for version in "${RUBY_VERSIONS[@]}"; do
    if [ "$version" = "latest" ]; then
      resolved_version=$(asdf latest ruby)
      print_with_color $BLUE "Resolved 'latest' to $resolved_version"
      resolved_versions+=("$resolved_version")
    else
      resolved_versions+=("$version")
    fi
  done

  # Install each Ruby version
  for version in "${resolved_versions[@]}"; do
    print_with_color $YELLOW "Installing Ruby $version"

    if ! asdf list ruby | grep -q "$version"; then
      asdf install ruby "$version"
      print_with_color $GREEN "Installed Ruby $version"
    else
      print_with_color $GREEN "Ruby $version already installed"
    fi

    # Install standard gems for this version
    install_gems_for_version "$version"
  done

  # Set default global version
  if [ "$DEFAULT_RUBY_VERSION" = "latest" ]; then
    default_version=$(asdf latest ruby)
  else
    default_version="$DEFAULT_RUBY_VERSION"
  fi

  asdf set -p ruby "$default_version"
  print_with_color $GREEN "Set Ruby $default_version as global version"

  print_with_color $GREEN 'Ruby setup complete!'
  print_with_color $BLUE "Run 'ruby --version' to verify installation"
  print_with_color $BLUE "Installed versions: ${resolved_versions[*]}"
}

print_with_color $YELLOW 'Setup Ruby development environment? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_ruby;;
  * ) print_with_color $GREEN 'skipping...';;
esac
