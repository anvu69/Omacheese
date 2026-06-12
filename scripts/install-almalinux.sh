#!/usr/bin/env bash
set -euo pipefail

sudo dnf update -y
sudo dnf install -y epel-release
sudo dnf config-manager --set-enabled crb || true

sudo dnf install -y \
  git curl wget unzip zip ca-certificates util-linux-user \
  zsh tmux \
  fzf ripgrep fd-find eza bat zoxide \
  gcc gcc-c++ make cmake ninja-build gettext \
  python3 python3-pip python3-virtualenv pipx \
  nodejs npm \
  golang \
  ansible-core \
  postgresql mysql sqlite redis

pipx ensurepath || true
pipx install pgcli || true
pipx install mycli || true
pipx install litecli || true

# LazyVim dependencies
npm install -g neovim prettier eslint_d typescript typescript-language-server || true

# Oh My Zsh. Safe to rerun; it skips when already installed.
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true
fi

# Use zsh as default shell
if command -v zsh >/dev/null 2>&1; then
  chsh -s "$(command -v zsh)" "$USER" || true
fi

echo "Done. Copy configs/zsh/zshrc to ~/.zshrc and configs/zsh/aliases.zsh to ~/.config/zsh/aliases.zsh."
echo "Install Neovim stable manually or via bob/mise if distro package is old."
