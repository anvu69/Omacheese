#!/usr/bin/env bash
set -euo pipefail

sudo dnf update -y

sudo dnf install -y \
  git \
  curl \
  wget \
  unzip \
  tar \
  zsh \
  util-linux-user \
  fzf \
  ripgrep \
  fd-find \
  eza \
  bat \
  zoxide \
  tmux \
  neovim \
  python3 \
  python3-pip \
  pipx \
  ansible

# Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Make zsh the default shell
if command -v zsh >/dev/null 2>&1; then
  if [ "$SHELL" != "$(command -v zsh)" ]; then
    chsh -s "$(command -v zsh)" || true
  fi
fi

# zoxide init hint
grep -q "zoxide init zsh" "$HOME/.zshrc" 2>/dev/null || {
  echo 'eval "$(zoxide init zsh)"' >> "$HOME/.zshrc"
}

echo "AlmaLinux dev packages installed."
echo "If shell did not change immediately, run: wsl --shutdown from Windows, then reopen Alacritty."