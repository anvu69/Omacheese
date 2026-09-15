# Aliases, PowerShell, Oh My Posh, Zsh

Shell layer là phần dùng nhiều nhất trong combo này. Repo tách rõ 2 môi trường:

- **Windows host**: PowerShell 7 + Oh My Posh + PSReadLine Vi mode
- **WSL2 AlmaLinux**: Zsh + Oh My Zsh + aliases/functions + tmux

> Danh sách dưới đây được đối chiếu trực tiếp với file config. Bản trước của
> tài liệu này liệt kê khoảng một chục alias không hề tồn tại (`lg`, `ep`,
> `alma`, `dnfi`…, và `ss` trong khi profile chỉ định nghĩa `sshp`). Nếu bạn
> sửa config, sửa luôn bảng này — CI không kiểm tra được tài liệu.

## Windows: PowerShell 7

Config:

```text
configs/powershell/Microsoft.PowerShell_profile.ps1
configs/oh-my-posh/poweruser.omp.json
```

Cài bằng `./scripts/link-configs.ps1`.

Profile gồm:

- PSReadLine Vi mode + **con trỏ đổi hình theo mode** (không có cái này thì Vi
  mode là trò đoán mò)
- Prediction ListView (PS 7.2+), màu Tokyo Night
- PSFzf: `Ctrl+T` chọn file, `Alt+C` đổi thư mục
- Oh My Posh, zoxide, Terminal-Icons, posh-git
- `eza` nếu có, tự fallback `Get-ChildItem` nếu không

| Lệnh | Việc |
|---|---|
| `ll` `la` `l` `lt` | eza (fallback `Get-ChildItem`) |
| `cat` | bat (chỉ khi bat có sẵn) |
| `v` | nvim |
| `g` | git |
| `gs` | `git status --short --branch` |
| `ga` `gc` `gcm` `gp` `gl` `gd` `gco` `gb` | git |
| `glog` | `git log --oneline --graph --decorate -20` |
| `lg` | lazygit |
| `ss` | chọn SSH host bằng fzf rồi ssh |
| `sst` | chọn SSH host, mở trong tmux (qua WSL) |
| `ep` `ea` `es` `ek` | sửa profile / alacritty / ssh config / whkdrc |
| `alma` | mở AlmaLinux WSL |
| `which` | đường dẫn thật của một lệnh |
| `reload-profile` | nạp lại profile |
| `desktop` | start-desktop.ps1 |
| `keys` | bảng keybinding (như `SUPER + /`) |
| `omenu` | Omarchy menu (như `SUPER + SPACE`) |

## WSL2 AlmaLinux: Zsh

Config:

```text
configs/zsh/zshrc
configs/zsh/aliases.zsh
```

| Lệnh | Việc |
|---|---|
| `ls` `ll` `la` `l` `lt` `tree` | eza |
| `cat` | `bat --paging=never` |
| `grep` | rg |
| `v` `vi` `vim` | nvim |
| `g` `gs` `ga` `gc` `gcm` `gp` `gl` `gd` `gb` `gco` `glog` | git |
| `lg` | lazygit |
| `t` `ta` `tls` `tn` | tmux |
| `dnfi` `dnfs` `dnfu` `dnfr` | dnf |
| `d` `dc` `k` | docker / compose / kubectl |
| `ss` `sst` | SSH host picker (fzf), `sst` bọc trong tmux |
| `sshkeys` | `ssh-add -l` — xem Bitwarden đang đưa key nào vào WSL |
| `z` | zoxide (nạp trong zshrc) |

Zsh còn bật `zsh-autosuggestions` và `zsh-syntax-highlighting` nếu
`install-almalinux.sh` clone được chúng; nếu không, shell vẫn chạy bình thường.

## Cái bẫy alias trong function

`zsh` expand alias lúc **đọc định nghĩa function**, không phải lúc gọi. Nên
một `alias grep='rg'` đặt phía trên sẽ âm thầm viết lại mọi `grep` bên trong
thân function bên dưới.

Đó chính là cách `ss()` và `sst()` từng hỏng trong repo này: `grep -E` thành
`rg -E`, mà `-E` của ripgrep là `--encoding`:

```text
rg: error parsing flag -E: unknown encoding: ^Host
```

Trong function luôn dùng `command grep`, `command cat`. File `aliases.zsh` giờ
làm đúng như vậy.

Cùng lý do, `du` **không** bị alias thành `dnf update`. Ghi đè một lệnh POSIX
phổ biến như `du` chỉ lộ ra vào đúng lúc bạn không muốn.

## Nguyên tắc

- Alias dùng hằng ngày đặt trong `aliases.zsh` hoặc PowerShell profile.
- Secret, token, host thật không commit vào repo public.
- SSH host commit bản `config.example`; `~/.ssh/config` thật giữ private.
- Nếu alias phình to, tách tiếp thành `git.zsh`, `ssh.zsh`, `docker.zsh`.
