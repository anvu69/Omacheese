# Windows 11 Developer Power-User Setup

Repo này tổng hợp combo Windows 11 dành cho developer theo hướng **keyboard-first, tiling window manager, terminal-heavy, Vim/Neovim, WSL2, remote-first**.

## Stack chính

| Nhóm | Lựa chọn |
|---|---|
| Terminal | Alacritty |
| Windows shell | PowerShell 7 + Oh My Posh + PSReadLine Vi mode |
| Window manager | komorebi + whkd + yasb |
| Terminal session | tmux |
| Editor | LazyVim / Neovim |
| CLI productivity | fzf, ripgrep, fd, eza, bat, zoxide, aliases/functions |
| File search | Everything |
| Browser | Brave + Vimium C |
| Linux dev env | WSL2 + AlmaLinux + Zsh + Oh My Zsh |
| Automation | Ansible |
| Database management | DBeaver Community |
| SSH client manager | electerm |
| Password / SSH key manager | Bitwarden Desktop SSH Agent |
| SSH architecture | OpenSSH config + ProxyJump + optional electerm profiles |

## Triết lý setup

- Windows 11 là **host OS**: window manager, browser, file search, native GUI tools.
- WSL2 AlmaLinux là **dev/runtime OS**: shell, tmux, LazyVim, Ansible, CLI tools.
- SSH manual dùng **electerm + Bitwarden SSH Agent**.
- SSH daily/advanced dùng **Alacritty → WSL2 → tmux → ssh**.
- Jump server dùng **ProxyJump**, hạn chế `ForwardAgent yes`.
- Alias, shell profile và prompt là lớp thao tác hằng ngày, nên được version-control như dotfiles.
- Config nên lưu trong Git để dễ backup/migrate.

## Cài nhanh

Mở PowerShell với quyền user bình thường:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
./scripts/install-windows.ps1
```

Trong WSL2 AlmaLinux:

```bash
bash ./scripts/install-almalinux.sh
```

## Cấu trúc repo

```text
.
├── configs/
│   ├── alacritty/
│   ├── komorebi/
│   ├── whkd/
│   ├── yasb/
│   ├── tmux/
│   ├── zsh/
│   ├── ssh/
│   ├── powershell/
│   ├── oh-my-posh/
│   └── lazyvim/
├── docs/
│   ├── ssh-bitwarden-electerm.md
│   ├── jump-server.md
│   ├── aliases-and-shell.md
│   └── workflow.md
└── scripts/
    ├── install-windows.ps1
    ├── install-almalinux.sh
    └── link-configs.ps1
```

## Push lên GitHub

Tạo repo trống trên GitHub, ví dụ `windows11-dev-poweruser`, rồi chạy:

```bash
git branch -M main
git remote add origin git@github.com:<YOUR_USERNAME>/windows11-dev-poweruser.git
git add .
git commit -m "Initial Windows 11 power-user developer setup"
git push -u origin main
```

Nếu dùng HTTPS:

```bash
git remote add origin https://github.com/<YOUR_USERNAME>/windows11-dev-poweruser.git
```


## Shell layer

Repo có sẵn config cho:

```text
PowerShell 7 + Oh My Posh + PSReadLine Vi mode
Zsh + Oh My Zsh + aliases/functions
```

Xem chi tiết tại:

```text
docs/aliases-and-shell.md
```
