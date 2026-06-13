#!/usr/bin/env bash
set -euo pipefail

echo "==> Updating AlmaLinux packages"
sudo dnf update -y

echo "==> Enabling CRB + EPEL"
sudo dnf install -y dnf-plugins-core epel-release
sudo dnf config-manager --set-enabled crb || true
sudo dnf makecache -y

echo "==> Installing base packages"
sudo dnf install -y \
  git \
  curl \
  wget \
  unzip \
  tar \
  zsh \
  util-linux-user \
  tmux \
  python3 \
  python3-pip \
  gcc \
  gcc-c++ \
  make \
  openssl-devel \
  pkgconf-pkg-config

echo "==> Installing EPEL/dev CLI packages"
sudo dnf install -y \
  fzf \
  ripgrep \
  fd-find \
  bat \
  neovim \
  pipx \
  ansible-core || true

echo "==> Ensuring pipx"
if ! command -v pipx >/dev/null 2>&1; then
  python3 -m pip install --user pipx
  python3 -m pipx ensurepath || true
fi

export PATH="$HOME/.local/bin:$PATH"

echo "==> Installing Ansible full via pipx if needed"
if command -v pipx >/dev/null 2>&1; then
  if ! command -v ansible >/dev/null 2>&1; then
    pipx install --include-deps ansible || true
  fi
else
  python3 -m pip install --user ansible || true
fi

echo "==> Installing Rust toolchain for eza/zoxide fallback"
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

# shellcheck disable=SC1091
source "$HOME/.cargo/env" 2>/dev/null || true

echo "==> Installing eza fallback"
if ! command -v eza >/dev/null 2>&1; then
  cargo install eza || true
fi

echo "==> Installing zoxide fallback"
if ! command -v zoxide >/dev/null 2>&1; then
  cargo install zoxide --locked || true
fi

echo "==> Installing Oh My Zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "==> Setting zsh as default shell"
if command -v zsh >/dev/null 2>&1; then
  if [ "${SHELL:-}" != "$(command -v zsh)" ]; then
    chsh -s "$(command -v zsh)" || true
  fi
fi

echo "==> Ensuring shell paths"
grep -q 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || {
  echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> "$HOME/.zshrc"
}

grep -q 'zoxide init zsh' "$HOME/.zshrc" 2>/dev/null || {
  echo 'if command -v zoxide >/dev/null 2>&1; then eval "$(zoxide init zsh)"; fi' >> "$HOME/.zshrc"
}

echo ""
echo "AlmaLinux dev packages installed."
echo "If shell did not change immediately, run this from Windows:"
echo "  wsl --shutdown"
echo "Then reopen Alacritty."