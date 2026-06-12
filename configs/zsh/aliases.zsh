# Shared Zsh aliases/functions for AlmaLinux WSL2

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias home='cd ~'
alias dev='cd ~/dev'
alias c='clear'

# Listing / file operations
alias l='eza --icons --group-directories-first'
alias ll='eza -lah --icons --group-directories-first'
alias la='eza -lah --icons --group-directories-first'
alias lt='eza --tree --level=2 --icons --group-directories-first'
alias cat='bat'
alias grep='rg'
alias duu='ncdu'
alias path='echo $PATH | tr ":" "\n"'

# Editors
alias v='nvim'
alias vi='nvim'
alias vim='nvim'
alias svi='sudo nvim'

# Git
alias g='git'
alias gs='git status --short --branch'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gds='git diff --staged'
alias glog='git log --oneline --graph --decorate --all -n 30'
alias lg='lazygit'

# tmux
alias ta='tmux attach -t'
alias tls='tmux ls'
alias tn='tmux new-session -A -s'
alias tk='tmux kill-session -t'

# Docker / Kubernetes / Terraform, enabled when installed
alias d='docker'
alias dc='docker compose'
alias k='kubectl'
alias tf='terraform'

# AlmaLinux package helpers
alias dnfs='dnf search'
alias dnfi='sudo dnf install -y'
alias dnfu='sudo dnf update -y'
alias dnfr='sudo dnf remove -y'

# Networking / process helpers
alias ports='ss -tulpn'
alias myip='curl -s https://ifconfig.me && echo'
alias pingg='ping 8.8.8.8'

mkcd() {
  mkdir -p "$1" && cd "$1"
}

extract() {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar.bz2) tar xjf "$1" ;;
      *.tar.gz)  tar xzf "$1" ;;
      *.bz2)     bunzip2 "$1" ;;
      *.rar)     unrar x "$1" ;;
      *.gz)      gunzip "$1" ;;
      *.tar)     tar xf "$1" ;;
      *.tbz2)    tar xjf "$1" ;;
      *.tgz)     tar xzf "$1" ;;
      *.zip)     unzip "$1" ;;
      *.7z)      7z x "$1" ;;
      *)         echo "Cannot extract: $1" ;;
    esac
  else
    echo "Not a file: $1"
  fi
}

# SSH host picker from ~/.ssh/config
ss() {
  local host
  host=$(grep -E "^Host " ~/.ssh/config 2>/dev/null \
    | awk '{print $2}' \
    | grep -v '[*?]' \
    | fzf --prompt='SSH > ')
  [ -n "$host" ] && ssh "$host"
}

sst() {
  local host
  host=$(grep -E "^Host " ~/.ssh/config 2>/dev/null \
    | awk '{print $2}' \
    | grep -v '[*?]' \
    | fzf --prompt='SSH tmux > ')
  [ -n "$host" ] && tmux new-session -A -s "$host" "ssh $host"
}

# Quick edit dotfiles
alias ez='nvim ~/.zshrc'
alias et='nvim ~/.tmux.conf'
alias es='nvim ~/.ssh/config'
