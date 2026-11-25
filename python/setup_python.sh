#!/bin/bash
. lib/helpers.sh

function setup_python() {
  install_package pyenv
  install_package pyenv-virtualenv

  # install uvx (python package manager)
  curl -LsSf https://astral.sh/uv/install.sh | sh

  # voicemode Claude plugin launches `uv run voicemode` from the project cwd, so
  # the CLI must be on PATH globally (~/.local/bin) — not just in the plugin venv.
  if ! command -v voicemode >/dev/null 2>&1; then
    uv tool install voice-mode
  fi
}

print_with_color $YELLOW 'Setup python? (y/n)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_python;;
  * ) print_with_color $GREEN 'skipping...';;
esac
