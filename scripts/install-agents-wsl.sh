#!/usr/bin/env bash
# Install the coding agents inside the WSL distro.
#
#   wsl -d AlmaLinux-9 -- bash ~/.config/omacheese/install-agents.sh
#   bash ./scripts/install-agents-wsl.sh claude codex
#
# Deliberately not part of install-almalinux.sh. That script provisions the dev
# environment every WSL user needs; agents are a few hundred MB, need a login
# per agent, and most machines here only ever use the Windows copies. So it is
# opt-in, and omacheese-agent.ps1 -Wsl points at it when it finds nothing.
#
# Claude Code is the exception to the Node rule: it ships a native Linux binary,
# so it installs on a box with no Node at all. The npm agents pull Node in
# first, from nodesource, because AlmaLinux 9's stream is too old for them.

set -uo pipefail

say()  { printf '\n==> %s\n' "$1"; }
warn() { printf '    !! %s\n' "$1" >&2; }

# Anything under /mnt is the Windows copy reaching in over the interop PATH.
# It is a shim around a .exe and cannot serve as the Linux install.
have() {
  local p
  p="$(command -v "$1" 2>/dev/null)" || return 1
  case "$p" in /mnt/*) return 1 ;; *) return 0 ;; esac
}

ensure_node() {
  have node && return 0
  say "Installing Node.js 22 (nodesource)"
  curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash - || {
    warn "nodesource failed; falling back to the distro stream"
    sudo dnf module install -y nodejs:20/common || return 1
  }
  sudo dnf install -y nodejs || return 1
}

install_claude() {
  curl -fsSL https://claude.ai/install.sh | bash
}
install_codex()    { ensure_node && npm install -g @openai/codex; }
install_gemini()   { ensure_node && npm install -g @google/gemini-cli; }
install_opencode() { curl -fsSL https://opencode.ai/install | bash; }
install_copilot()  { ensure_node && npm install -g @github/copilot; }
install_crush()    { ensure_node && npm install -g @charmland/crush; }
install_cursor()   { curl https://cursor.com/install -fsS | bash; }

# claude first: it is the default agent and the only one with no prerequisite.
ALL="claude codex gemini opencode"
WANT="${*:-$ALL}"

failed=""
for agent in $WANT; do
  cmd="$agent"
  [ "$agent" = "cursor" ] && cmd="cursor-agent"

  if have "$cmd"; then
    say "$agent already installed ($(command -v "$cmd"))"
    continue
  fi

  say "Installing $agent"
  # `|| true` on purpose: one agent failing to install should not stop the rest.
  if ! "install_$agent"; then
    warn "$agent failed"
    failed="$failed $agent"
  fi
done

# ~/.local/bin is where both the claude and opencode installers land, and it is
# already on PATH in this repo's zshrc. Say so rather than leave a fresh shell
# reporting "command not found" on something that did install.
say "Done"
printf '    Open a new shell (or: export PATH="$HOME/.local/bin:$PATH") before using them.\n'
[ -n "$failed" ] && { warn "failed:$failed"; exit 1; }
exit 0
