#!/usr/bin/env bash
# Copy the Linux-side configs into $HOME.
#
#   bash ./scripts/install-configs-wsl.sh [source-dir]
#
# source-dir defaults to the repo this script lives in; bootstrap-almalinux.sh
# passes the temp directory it downloaded into. One copy of this list, used by
# both paths: before, only the curl | bash bootstrap installed these files, and
# anyone working from a clone - which is what install-wsl.ps1 now tells you to
# do - was handed "cp configs/zsh/zshrc ~/.zshrc etc." and left to work the
# rest out, so ~/.config/wsl/wsl.conf did not exist and the next instruction
# (sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf) failed.

set -euo pipefail

SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

if [ ! -d "$SRC/configs" ]; then
  echo "install-configs-wsl.sh: no configs/ under $SRC" >&2
  exit 1
fi

backup() {
  [ -e "$1" ] && cp -a "$1" "$1.$(date +%Y%m%d-%H%M%S).bak" && echo "  ~ backed up $1"
  return 0
}

mkdir -p "$HOME/.config/zsh" "$HOME/.config/wsl" "$HOME/.config/oh-my-posh" "$HOME/.config/ai"

backup "$HOME/.zshrc";     cp "$SRC/configs/zsh/zshrc"      "$HOME/.zshrc"
backup "$HOME/.tmux.conf"; cp "$SRC/configs/tmux/tmux.conf" "$HOME/.tmux.conf"
backup "$HOME/.gitconfig"; cp "$SRC/configs/git/gitconfig"  "$HOME/.gitconfig"

cp "$SRC/configs/zsh/aliases.zsh"                "$HOME/.config/zsh/aliases.zsh"
cp "$SRC/configs/zsh/agent-layouts.zsh"          "$HOME/.config/zsh/agent-layouts.zsh"
cp "$SRC/configs/wsl/ssh-agent-bridge.sh"        "$HOME/.config/wsl/ssh-agent-bridge.sh"
cp "$SRC/configs/wsl/wsl.conf"                   "$HOME/.config/wsl/wsl.conf"
cp "$SRC/configs/oh-my-posh/poweruser.omp.json"  "$HOME/.config/oh-my-posh/poweruser.omp.json"
chmod +x "$HOME/.config/wsl/ssh-agent-bridge.sh"

# AI stack. .env is never overwritten - it holds the HF token.
cp "$SRC/configs/ai/docker-compose.vllm.yml"     "$HOME/.config/ai/"
cp "$SRC/configs/ai/docker-compose.finetune.yml" "$HOME/.config/ai/"
cp "$SRC/configs/ai/.env.example"                "$HOME/.config/ai/"
[ -f "$HOME/.config/ai/.env" ] || cp "$SRC/configs/ai/.env.example" "$HOME/.config/ai/.env"

printf '\nLinux configs installed.\n'

# Only what is actually still undone. From setup.ps1 the distro step writes
# /etc/wsl.conf and restarts the distro itself, so printing "sudo cp ... &&
# wsl --shutdown" there sent people to redo finished work. The curl bootstrap
# has no Windows side to do it, so it still gets told.
if ! grep -qs '^appendWindowsPath=false' /etc/wsl.conf || ! grep -qs '^default=' /etc/wsl.conf; then
  cat <<'EOF'

Still to do (needs root, and a restart of the distro):
  sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf
  # then, from Windows:
  wsl --shutdown
EOF
fi

if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
  cat <<'EOF'

Set your git identity (deliberately not shipped in the repo):
  git config --global user.name  "Your Name"
  git config --global user.email "you@example.com"
EOF
fi
