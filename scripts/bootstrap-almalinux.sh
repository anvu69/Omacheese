#!/usr/bin/env bash
# Bootstrap the AlmaLinux (WSL2) side from GitHub Raw, without cloning.
#
#   repo="https://raw.githubusercontent.com/anvu69/Omacheese/main"
#   curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo"

set -euo pipefail

REPO_RAW_BASE=""
SKIP_INSTALL=0
SKIP_CONFIGS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         REPO_RAW_BASE="${2:-}"; shift 2 ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --skip-configs) SKIP_CONFIGS=1; shift ;;
    -h|--help)
      sed -n '2,8p' "$0"; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$REPO_RAW_BASE" ] || REPO_RAW_BASE="${DEV_REPO_RAW:-}"

if [ -z "$REPO_RAW_BASE" ]; then
  echo "Missing --repo https://raw.githubusercontent.com/<user>/Omacheese/main" >&2
  exit 1
fi

REPO_RAW_BASE="${REPO_RAW_BASE%/}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

download() {
  local remote="$1" local_path="$2"
  echo "  . $remote"
  mkdir -p "$(dirname "$local_path")"
  curl -fsSL "$REPO_RAW_BASE/$remote" -o "$local_path"
}

if [ "$SKIP_INSTALL" -eq 0 ]; then
  echo "Downloading installer"
  download "scripts/install-almalinux.sh" "$WORKDIR/scripts/install-almalinux.sh"
  bash "$WORKDIR/scripts/install-almalinux.sh"
fi

if [ "$SKIP_CONFIGS" -eq 0 ]; then
  echo "Downloading configs"
  for f in \
    "configs/zsh/zshrc" \
    "configs/zsh/aliases.zsh" \
    "configs/zsh/agent-layouts.zsh" \
    "configs/tmux/tmux.conf" \
    "configs/wsl/wsl.conf" \
    "configs/wsl/ssh-agent-bridge.sh" \
    "configs/git/gitconfig" \
    "configs/oh-my-posh/poweruser.omp.json" \
    "configs/ai/docker-compose.vllm.yml" \
    "configs/ai/docker-compose.finetune.yml" \
    "configs/ai/.env.example"
  do
    download "$f" "$WORKDIR/$f"
  done

  backup() {
    [ -e "$1" ] && cp -a "$1" "$1.$(date +%Y%m%d-%H%M%S).bak" && echo "  ~ backed up $1"
    return 0
  }

  mkdir -p "$HOME/.config/zsh" "$HOME/.config/wsl" "$HOME/.config/oh-my-posh" "$HOME/.config/ai"

  backup "$HOME/.zshrc";     cp "$WORKDIR/configs/zsh/zshrc"        "$HOME/.zshrc"
  backup "$HOME/.tmux.conf"; cp "$WORKDIR/configs/tmux/tmux.conf"   "$HOME/.tmux.conf"
  backup "$HOME/.gitconfig"; cp "$WORKDIR/configs/git/gitconfig"    "$HOME/.gitconfig"

  cp "$WORKDIR/configs/zsh/aliases.zsh"              "$HOME/.config/zsh/aliases.zsh"
  cp "$WORKDIR/configs/zsh/agent-layouts.zsh"        "$HOME/.config/zsh/agent-layouts.zsh"
  cp "$WORKDIR/configs/wsl/ssh-agent-bridge.sh"      "$HOME/.config/wsl/ssh-agent-bridge.sh"
  cp "$WORKDIR/configs/wsl/wsl.conf"                 "$HOME/.config/wsl/wsl.conf"
  cp "$WORKDIR/configs/oh-my-posh/poweruser.omp.json" "$HOME/.config/oh-my-posh/poweruser.omp.json"
  chmod +x "$HOME/.config/wsl/ssh-agent-bridge.sh"

  # AI stack. .env is never overwritten - it holds the HF token.
  cp "$WORKDIR/configs/ai/docker-compose.vllm.yml"     "$HOME/.config/ai/"
  cp "$WORKDIR/configs/ai/docker-compose.finetune.yml" "$HOME/.config/ai/"
  cp "$WORKDIR/configs/ai/.env.example"                "$HOME/.config/ai/"
  [ -f "$HOME/.config/ai/.env" ] || cp "$WORKDIR/configs/ai/.env.example" "$HOME/.config/ai/.env"

  cat <<'EOF'

Linux configs installed.

Still to do (needs root, and a restart of the distro):
  sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf
  # then, from Windows:
  wsl --shutdown

Set your git identity (deliberately not shipped in the repo):
  git config --global user.name  "Your Name"
  git config --global user.email "you@example.com"
EOF
fi
