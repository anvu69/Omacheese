#!/usr/bin/env bash
# Bridge the Windows SSH agent (Bitwarden Desktop) into WSL.
#
# The problem this solves: Bitwarden's SSH agent runs on the Windows side and
# speaks over a named pipe. WSL's ssh wants a unix socket, so without a relay
# every `ssh` inside WSL has no keys at all - which is exactly the daily flow
# this repo documents (Alacritty -> WSL -> tmux -> ssh).
#
# The relay is npiperelay.exe (Windows) piped through socat (Linux):
#
#     ssh (WSL) -> ~/.ssh/agent.sock -> socat -> npiperelay.exe
#               -> \\.\pipe\openssh-ssh-agent -> Bitwarden
#
# Requirements
#   Windows : winget install --id albertony.npiperelay -e
#             Bitwarden -> Settings -> enable SSH agent
#             Services  -> "OpenSSH Authentication Agent" -> Disabled
#                         (Bitwarden needs that pipe name for itself)
#   WSL     : sudo dnf install -y socat
#
# Source this from ~/.zshrc (the repo's zshrc already does).

_bw_agent_sock="${HOME}/.ssh/agent.sock"

_bw_find_npiperelay() {
  # Prefer one on PATH, then the usual winget install locations. Keeping this
  # lookup cheap matters: it runs on every shell start.
  if command -v npiperelay.exe >/dev/null 2>&1; then
    command -v npiperelay.exe
    return 0
  fi

  local candidate
  for candidate in \
    "/mnt/c/Program Files/npiperelay/npiperelay.exe" \
    "/mnt/c/Users/${USER}/AppData/Local/Microsoft/WinGet/Links/npiperelay.exe" \
    "/mnt/c/ProgramData/chocolatey/bin/npiperelay.exe"
  do
    [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done

  return 1
}

bw_agent_start() {
  local relay
  relay="$(_bw_find_npiperelay)" || {
    echo "npiperelay.exe not found. On Windows run:" >&2
    echo "  winget install --id albertony.npiperelay -e" >&2
    return 1
  }

  command -v socat >/dev/null 2>&1 || {
    echo "socat not found. Run: sudo dnf install -y socat" >&2
    return 1
  }

  mkdir -p "$(dirname "$_bw_agent_sock")"
  chmod 700 "$(dirname "$_bw_agent_sock")"

  # A stale socket file survives reboots and makes socat refuse to bind.
  # Only remove it when nothing is actually listening.
  if ! ss -a 2>/dev/null | grep -q "$_bw_agent_sock"; then
    rm -f "$_bw_agent_sock"
  fi

  if [ ! -S "$_bw_agent_sock" ]; then
    (
      setsid socat \
        "UNIX-LISTEN:${_bw_agent_sock},fork,mode=600" \
        "EXEC:\"${relay}\" -ei -s //./pipe/openssh-ssh-agent,nofork" \
        >/dev/null 2>&1 &
    ) >/dev/null 2>&1
    # Give socat a moment to create the socket before the shell moves on.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      [ -S "$_bw_agent_sock" ] && break
      sleep 0.1
    done
  fi

  export SSH_AUTH_SOCK="$_bw_agent_sock"
}

bw_agent_status() {
  if [ ! -S "$_bw_agent_sock" ]; then
    echo "bridge socket missing: $_bw_agent_sock"
    return 1
  fi
  SSH_AUTH_SOCK="$_bw_agent_sock" ssh-add -l
}

bw_agent_restart() {
  pkill -f "UNIX-LISTEN:${_bw_agent_sock}" 2>/dev/null
  rm -f "$_bw_agent_sock"
  bw_agent_start
}

# Start it silently on shell init; failures should never block a login shell.
bw_agent_start >/dev/null 2>&1 || true
