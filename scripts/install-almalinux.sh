#!/usr/bin/env bash
# AlmaLinux (WSL2) dev environment.
#
#   bash ./scripts/install-almalinux.sh
#
# Installs packages and Oh My Zsh plugins only. It deliberately does NOT write
# to ~/.zshrc: bootstrap-almalinux.sh copies the repo's zshrc over it straight
# afterwards, so anything appended here would be wiped. Everything this script
# used to append already lives in configs/zsh/zshrc.

set -euo pipefail

say() { printf '\n==> %s\n' "$1"; }

say "Updating AlmaLinux packages"
sudo dnf update -y

say "Enabling CRB + EPEL"
sudo dnf install -y dnf-plugins-core epel-release
sudo dnf config-manager --set-enabled crb || true
sudo dnf makecache -y

say "Installing base packages"
sudo dnf install -y \
  git curl wget unzip tar \
  zsh util-linux-user tmux \
  python3 python3-pip \
  gcc gcc-c++ make cmake \
  openssl-devel pkgconf-pkg-config \
  socat

say "Installing CLI tooling"
# `|| true` because EPEL package names drift between minor releases and a
# missing extra should not abort the whole run.
sudo dnf install -y \
  fzf ripgrep fd-find bat neovim jq pipx ansible-core || true

say "Ensuring pipx"
if ! command -v pipx >/dev/null 2>&1; then
  python3 -m pip install --user pipx
  python3 -m pipx ensurepath || true
fi
export PATH="$HOME/.local/bin:$PATH"

say "Installing Ansible"
if ! command -v ansible >/dev/null 2>&1; then
  if command -v pipx >/dev/null 2>&1; then
    pipx install --include-deps ansible || true
  else
    python3 -m pip install --user ansible || true
  fi
fi

say "Installing Rust toolchain (for eza/zoxide)"
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env" 2>/dev/null || true

# --locked on both. Without it cargo resolves every dependency afresh to the
# newest semver-compatible release, and for eza 0.23.5 that picked a palette
# crate its code does not build against - "error[E0433]: cannot find `lms` in
# `crate`" - while the `|| true` below turned the failure into silence: zoxide
# (already --locked) installed, eza did not, and nothing said so.
command -v eza    >/dev/null 2>&1 || cargo install eza --locked || true
command -v zoxide >/dev/null 2>&1 || cargo install zoxide --locked || true

say "Installing Oh My Zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

say "Installing Zsh plugins"
# The repo's zshrc enables these only when the directories exist, so a failed
# clone degrades to a plain prompt instead of a broken shell.
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  target="$ZSH_CUSTOM/plugins/$plugin"
  if [ ! -d "$target" ]; then
    git clone --depth=1 "https://github.com/zsh-users/$plugin" "$target" || true
  fi
done

say "Installing oh-my-posh (shared prompt with the Windows side)"
if ! command -v oh-my-posh >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin" || true
fi

say "Setting zsh as the default shell"
# usermod through sudo, not chsh. chsh run as the user authenticates through
# PAM and asks for the account password; with no console - a setup step - it
# fails, and the `|| true` that used to follow hid it, so zsh was installed and
# configured and never became the shell anyone got.
if command -v zsh >/dev/null 2>&1; then
  zsh_path="$(command -v zsh)"
  if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]; then
    sudo usermod -s "$zsh_path" "$USER"
  fi
fi

# Run from a clone, the configs are right here, so install them rather than
# printing "cp configs/zsh/zshrc ~/.zshrc etc." and leaving the rest to the
# reader - the step after it (sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf)
# depends on a file that copying never produced. Under bootstrap-almalinux.sh
# this script arrives alone in a temp directory, so the guard is false there
# and the bootstrap does the copying itself.
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$REPO_DIR/configs" ]; then
  say "Installing the Linux configs from $REPO_DIR"
  bash "$REPO_DIR/scripts/install-configs-wsl.sh" "$REPO_DIR"
fi

# No "Next:" list. /etc/wsl.conf, the default user, the distro restart and
# npiperelay on the Windows side are all done by scripts/install-distro.ps1,
# which is what runs this script.
printf '\nAlmaLinux dev environment installed.\n'
