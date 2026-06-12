# Aliases, PowerShell, Oh My Posh, Zsh, Oh My Zsh

Shell layer là phần dùng nhiều nhất trong combo này. Repo tách rõ 2 môi trường:

- Windows host: PowerShell 7 + Oh My Posh + PSReadLine Vi mode.
- WSL2 AlmaLinux: Zsh + Oh My Zsh + aliases/functions + tmux.

## Windows: PowerShell + Oh My Posh

Config mẫu nằm ở:

```text
configs/powershell/Microsoft.PowerShell_profile.ps1
configs/oh-my-posh/poweruser.omp.json
```

Link/copy config bằng:

```powershell
./scripts/link-configs.ps1
```

Profile bao gồm:

- PSReadLine Vi mode.
- Oh My Posh theme riêng.
- Terminal-Icons.
- zoxide.
- Git aliases.
- SSH host picker dùng `fzf`.
- Shortcut mở nhanh Alacritty/SSH/profile.

Các alias quan trọng:

```powershell
v       # nvim
g       # git
ll/la   # eza fallback Get-ChildItem
gs      # git status --short --branch
lg      # lazygit
ss      # chọn SSH host từ ~/.ssh/config bằng fzf
sst     # chọn SSH host và mở tmux session trong WSL
ep      # edit PowerShell profile
ea      # edit Alacritty config
es      # edit SSH config
alma    # mở AlmaLinux WSL
```

## WSL2 AlmaLinux: Zsh + Oh My Zsh

Config mẫu nằm ở:

```text
configs/zsh/zshrc
configs/zsh/aliases.zsh
```

Sau khi chạy install script, copy/link config:

```bash
mkdir -p ~/.config/zsh
cp configs/zsh/zshrc ~/.zshrc
cp configs/zsh/aliases.zsh ~/.config/zsh/aliases.zsh
```

Aliases quan trọng:

```bash
v/vi/vim       # nvim
ll/la/l/lt     # eza
cat            # bat
grep           # rg
z              # zoxide cd smart
ss             # SSH host picker
sst            # SSH host picker + tmux session
tn             # tmux new-session -A -s
ta             # tmux attach -t
lg             # lazygit
dnfi/dnfu      # dnf helpers
```

## Nguyên tắc

- Alias dùng hằng ngày đặt trong `aliases.zsh` hoặc PowerShell profile.
- Secret, token, host thật không commit vào repo public.
- SSH host có thể commit bản `config.example`; file thật `~/.ssh/config` nên private.
- Nếu alias bắt đầu phình to, tách tiếp thành `git.zsh`, `ssh.zsh`, `docker.zsh`.
