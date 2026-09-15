# ~/.config/zsh/aliases.zsh
#
# NOTE ON ALIASES INSIDE FUNCTIONS
# zsh expands aliases when a function DEFINITION is parsed, not when it runs.
# So an `alias grep='rg'` above a function silently rewrites every `grep`
# inside that function's body. That is how ss()/sst() below used to break:
# `grep -E` became `rg -E`, and ripgrep reads -E as --encoding, so the host
# picker died with "unknown encoding: ^Host ".
# Inside functions, always use `command grep`, `command cat`, etc.

# --- Navigation -------------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# --- Listing ----------------------------------------------------------------
alias ls='eza --icons --group-directories-first'
alias ll='eza -lah --icons --group-directories-first --git'
alias la='eza -la --icons --group-directories-first'
alias l='eza -lh --icons --group-directories-first'
alias lt='eza --tree --level=2 --icons'
alias tree='eza --tree --icons'

# --- Files ------------------------------------------------------------------
# --paging=never keeps `cat` behaving like cat when it is not a terminal.
alias cat='bat --paging=never'
alias grep='rg'
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

# --- Git --------------------------------------------------------------------
alias g='git'
alias gs='git status --short --branch'
alias ga='git add'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'
alias glog='git log --oneline --graph --decorate -20'
alias lg='lazygit'

# --- tmux -------------------------------------------------------------------
alias t='tmux'
alias ta='tmux attach -t'
alias tls='tmux ls'
alias tn='tmux new-session -A -s'

# --- dnf --------------------------------------------------------------------
# Deliberately NOT `du`: that shadows disk-usage, and you find out at the
# worst possible moment.
alias dnfi='sudo dnf install -y'
alias dnfs='dnf search'
alias dnfu='sudo dnf update -y'
alias dnfr='sudo dnf remove -y'

# --- Containers / k8s -------------------------------------------------------
alias d='docker'
alias dc='docker compose'
alias k='kubectl'

# --- SSH --------------------------------------------------------------------
# Pick a host out of ~/.ssh/config with fzf and connect.
ss() {
  local host
  host=$(command grep -E "^Host " "$HOME/.ssh/config" 2>/dev/null \
    | awk '{for (i=2; i<=NF; i++) print $i}' \
    | command grep -v "[*?]" \
    | sort -u \
    | fzf --prompt="ssh > " --height=40% --layout=reverse)

  [ -n "$host" ] && ssh "$host"
}

# Same, but inside a tmux session named after the host, so a dropped
# connection does not lose the work.
sst() {
  local host
  host=$(command grep -E "^Host " "$HOME/.ssh/config" 2>/dev/null \
    | awk '{for (i=2; i<=NF; i++) print $i}' \
    | command grep -v "[*?]" \
    | sort -u \
    | fzf --prompt="ssh+tmux > " --height=40% --layout=reverse)

  [ -n "$host" ] && tmux new-session -A -s "$host" "ssh $host"
}

# Show which keys the Bitwarden bridge is currently offering.
alias sshkeys='ssh-add -l'
