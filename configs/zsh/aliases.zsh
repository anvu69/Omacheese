# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Listing
alias ls='eza --icons --group-directories-first'
alias ll='eza -lah --icons --group-directories-first'
alias la='eza -la --icons --group-directories-first'
alias tree='eza --tree --icons'

# Files
alias cat='bat'
alias grep='rg'

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'

# tmux
alias t='tmux'
alias ta='tmux attach'
alias tls='tmux ls'
alias tn='tmux new -s'

# dnf
alias di='sudo dnf install -y'
alias ds='dnf search'
alias du='sudo dnf update -y'
alias dr='sudo dnf remove -y'

# Docker
alias d='docker'
alias dc='docker compose'

# Kubernetes
alias k='kubectl'

# SSH host picker
ss() {
  local host
  host=$(grep -E "^Host " "$HOME/.ssh/config" 2>/dev/null \
    | awk '{print $2}' \
    | grep -v "[*?]" \
    | fzf --prompt="SSH > ")

  [ -n "$host" ] && ssh "$host"
}

sst() {
  local host
  host=$(grep -E "^Host " "$HOME/.ssh/config" 2>/dev/null \
    | awk '{print $2}' \
    | grep -v "[*?]" \
    | fzf --prompt="SSH tmux > ")

  [ -n "$host" ] && tmux new-session -A -s "$host" "ssh $host"
}