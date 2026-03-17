#!/bin/bash
. lib/helpers.sh

function setup_python() {
  install_package pyenv
  install_package pyenv-virtualenv

  # install uvx (python package manager)
  curl -LsSf https://astral.sh/uv/install.sh | sh

  # obsidian tagging pipeline venv
  setup_obsidian_tagging_venv
}

OBSIDIAN_TAGGING_VENV="$HOME/.venvs/obsidian-tagging"

function setup_obsidian_tagging_venv() {
  print_with_color $BLUE 'Setting up obsidian-tagging venv...'
  uv venv "$OBSIDIAN_TAGGING_VENV" --python 3.12
  uv pip install --python "$OBSIDIAN_TAGGING_VENV/bin/python" \
    anthropic redis sentence-transformers
  print_with_color $GREEN 'obsidian-tagging venv ready'
}

print_with_color $YELLOW 'Setup python? (y/n)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_python;;
  * ) print_with_color $GREEN 'skipping...';;
esac
