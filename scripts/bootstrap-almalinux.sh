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
    "configs/ai/.env.example" \
    "scripts/install-configs-wsl.sh"
  do
    download "$f" "$WORKDIR/$f"
  done

  # The copying lives in one place, shared with the clone path, so the two
  # cannot drift: install-almalinux.sh runs the same script when it finds a
  # configs/ directory next to itself.
  bash "$WORKDIR/scripts/install-configs-wsl.sh" "$WORKDIR"
fi
