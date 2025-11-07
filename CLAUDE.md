# Dotfiles Repository Guide

## Commands
- Setup all tools: `./install.sh`
- Setup specific tool: `./<tool_dir>/setup_<tool>.sh`
- Neovim: Check plugin status with `:checkhealth`
- Reload config: `:so` (in Neovim) or `source ~/.zshrc` (for shell)

## Code Style Guidelines
- **Shell scripts**: Use helpers from `lib/helpers.sh` for consistency
- **Neovim config**: Modular organization under `nvim/lua/mpataki/`
- **Lua**: Use 2-space indentation, camelCase for variables
- **File organization**: Each tool has its own directory with setup script
- **Scripts**: Include platform detection for cross-compatibility
- **Error handling**: Use `set -e` in critical shell scripts
- **Comments**: Document non-obvious configurations or workarounds
- **Commit messages**: Use present tense, descriptive summaries

## Platform Support
This repository supports both macOS and Linux (primarily Arch) configurations.