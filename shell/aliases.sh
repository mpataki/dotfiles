alias e='nvim'

# bundler
alias be='bundle exec'

# git
alias g='git'
alias gadd='git add -u && git add . && git status --short'
alias gs='git status --short'
alias gap='git add --patch'
alias ga='git add'
alias gd='git diff'
alias gc='git commit -m'
alias gpl='git pull --rebase'
alias gps='git push'
alias gco='git checkout'
alias gcp='git cherry-pick'
alias gpr='git pull-request'
alias gb='git brach --all --verbose'

gwt() {
    local branch="$1"
    local worktree_path="${2:-../$1}"
    
    # Ensure git is available
    if ! command -v git &> /dev/null; then
        echo "Error: git command not found" >&2
        return 1
    fi
    
    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        git worktree add -b "$branch" "$worktree_path"
    else
        git worktree add "$worktree_path" "$branch"
    fi
    
    echo "Worktree created at $worktree_path"
    echo "Switching to $worktree_path"
    cd $worktree_path
}

gwt-rm() {
    local worktree_path="${1:-../$(basename $(pwd))}"
    git worktree remove "$worktree_path"
}

# tmux
alias ta='tmux attach -t'
alias tad='tmux attach -d -t'
alias ts='tmux new-session -s'
alias tl='tmux list-sessions'
alias tksv='tmux kill-server'
alias tkss='tmux kill-session -t'

# system
alias ls='ls -G' # turn on colors
alias pacman='sudo pacman'
alias systemctl='sudo systemctl'

alias cc='claude "read CLAUDE.md carefully. make sure you follow all of the defined rules and settings for code style, comments, testing, the development process and diagnostics like using an lsp via mcp when available."'
