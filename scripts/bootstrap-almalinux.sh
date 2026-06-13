#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_BASE=""
SKIP_INSTALL=0
SKIP_CONFIGS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      REPO_RAW_BASE="${2:-}"
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
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [ -z "$REPO_RAW_BASE" ]; then
  REPO_RAW_BASE="${DEV_REPO_RAW:-}"
fi

if [ -z "$REPO_RAW_BASE" ]; then
  echo "Missing --repo https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
  exit 1
fi

REPO_RAW_BASE="${REPO_RAW_BASE%/}"
WORKDIR="$(mktemp -d)"

download() {
  local remote_path="$1"
  local local_path="$2"

  echo "Downloading $remote_path"
  mkdir -p "$(dirname "$local_path")"
  curl -fsSL "$REPO_RAW_BASE/$remote_path" -o "$local_path"
}

if [ "$SKIP_INSTALL" -eq 0 ]; then
  download "scripts/install-almalinux.sh" "$WORKDIR/scripts/install-almalinux.sh"
  bash "$WORKDIR/scripts/install-almalinux.sh"
fi

if [ "$SKIP_CONFIGS" -eq 0 ]; then
  download "configs/zsh/zshrc" "$WORKDIR/configs/zsh/zshrc"
  download "configs/zsh/aliases.zsh" "$WORKDIR/configs/zsh/aliases.zsh"
  download "configs/tmux/tmux.conf" "$WORKDIR/configs/tmux/tmux.conf"
  download "configs/lazyvim/README.md" "$WORKDIR/configs/lazyvim/README.md"

  mkdir -p "$HOME/.config/zsh"
  cp "$WORKDIR/configs/zsh/zshrc" "$HOME/.zshrc"
  cp "$WORKDIR/configs/zsh/aliases.zsh" "$HOME/.config/zsh/aliases.zsh"
  cp "$WORKDIR/configs/tmux/tmux.conf" "$HOME/.tmux.conf"

  echo "Linux configs installed."
fi