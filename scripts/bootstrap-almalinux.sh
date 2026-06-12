#!/usr/bin/env bash
# Bootstrap AlmaLinux WSL setup without cloning the full repo.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<USER>/windows11-dev-poweruser/main/scripts/bootstrap-almalinux.sh | bash -s -- --repo https://raw.githubusercontent.com/<USER>/windows11-dev-poweruser/main

set -euo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"
SKIP_INSTALL=0
SKIP_CONFIGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_RAW_BASE="$2"
      shift 2
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --skip-configs)
      SKIP_CONFIGS=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$REPO_RAW_BASE" == *"<YOUR_USERNAME>"* ]]; then
  echo "Set --repo to your GitHub raw URL, e.g. https://raw.githubusercontent.com/inkman/windows11-dev-poweruser/main" >&2
  exit 1
fi

WORKDIR="${TMPDIR:-/tmp}/windows11-dev-poweruser-bootstrap"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

fetch() {
  local remote_path="$1"
  local local_path="$2"
  mkdir -p "$(dirname "$local_path")"
  echo "Downloading $remote_path"
  curl -fsSL "$REPO_RAW_BASE/$remote_path" -o "$local_path"
}

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  fetch "scripts/install-almalinux.sh" "$WORKDIR/install-almalinux.sh"
  bash "$WORKDIR/install-almalinux.sh"
fi

if [[ "$SKIP_CONFIGS" -eq 0 ]]; then
  fetch "configs/zsh/zshrc" "$WORKDIR/configs/zsh/zshrc"
  fetch "configs/zsh/aliases.zsh" "$WORKDIR/configs/zsh/aliases.zsh"
  fetch "configs/tmux/tmux.conf" "$WORKDIR/configs/tmux/tmux.conf"
  fetch "configs/ssh/config.example" "$WORKDIR/configs/ssh/config.example"

  mkdir -p "$HOME/.config/zsh" "$HOME/.ssh"
  cp "$WORKDIR/configs/zsh/zshrc" "$HOME/.zshrc"
  cp "$WORKDIR/configs/zsh/aliases.zsh" "$HOME/.config/zsh/aliases.zsh"
  cp "$WORKDIR/configs/tmux/tmux.conf" "$HOME/.tmux.conf"
  cp "$WORKDIR/configs/ssh/config.example" "$HOME/.ssh/config.example"
  chmod 700 "$HOME/.ssh"
fi

echo "AlmaLinux bootstrap complete. Restart shell or run: exec zsh"
echo "Review ~/.ssh/config.example before renaming it to config."
