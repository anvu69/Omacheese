# Windows 11 Developer Power-User Setup

Combo Windows 11 cho developer theo hướng **keyboard-first, tiling window
manager, terminal-heavy, Vim/Neovim, WSL2, remote-first** — với navigation và
quản lý workspace port từ [Omarchy](https://omarchy.org).

```powershell
./scripts/install-windows.ps1     # cài package
./scripts/link-configs.ps1        # cài config + autostart
./scripts/doctor.ps1              # kiểm tra mọi thứ đã đúng
./scripts/start-desktop.ps1       # chạy komorebi + whkd + yasb
```

Rồi bấm **`SUPER + /`** để xem toàn bộ keybinding.

## Stack chính

| Nhóm | Lựa chọn |
|---|---|
| Terminal | Alacritty |
| Windows shell | PowerShell 7 + Oh My Posh + PSReadLine Vi mode |
| Window manager | komorebi + whkd + yasb |
| Keymap | Omarchy (SUPER-first), xem `docs/keybindings.md` |
| Terminal session | tmux |
| Editor | LazyVim / Neovim |
| CLI | fzf, ripgrep, fd, eza, bat, zoxide, delta, lazygit, gh, jq |
| File search | Everything |
| Browser | Brave + Vimium C |
| Linux dev env | WSL2 + AlmaLinux + Zsh + Oh My Zsh |
| Database | DBeaver Community |
| SSH GUI | electerm |
| SSH key / vault | Bitwarden Desktop SSH Agent (+ cầu nối vào WSL) |
| Theme | Tokyo Night (Omarchy palette), dùng chung mọi tool |

## Triết lý

- Windows 11 là **host OS**: window manager, browser, file search, GUI tools.
- WSL2 AlmaLinux là **dev/runtime OS**: shell, tmux, LazyVim, Ansible, CLI.
- SSH daily dùng **Alacritty → WSL2 → tmux → ssh**; electerm cho việc GUI.
- Jump server dùng **ProxyJump**, không dùng `ForwardAgent yes`.
- Config sống trong Git, cài bằng symlink để sửa là ăn ngay.
- **Mọi thứ phải verify được** — `doctor.ps1` và CI kiểm tra thay vì tin tưởng.

## Navigation kiểu Omarchy

`SUPER` là phím Windows. Một modifier quản cửa sổ, mỗi modifier thêm vào là
một chiều nhất quán:

| Phím | Ý nghĩa |
|---|---|
| `SUPER` | focus / đi tới |
| `SUPER + SHIFT` | mang cửa sổ theo |
| `SUPER + SHIFT + ALT` | gửi cửa sổ đi, mình ở lại |
| `SUPER + ALT` | nhóm (stack) |
| `SUPER + CTRL` | toggle hệ thống |

Vài phím đáng nhớ trước:

| Phím | Việc |
|---|---|
| `SUPER + /` | Bảng keybinding (search được) |
| `SUPER + SPACE` | Menu Omarchy |
| `SUPER + CTRL + TAB` | Workspace vừa rồi (back-and-forth) |
| `SUPER + 1…0` | Workspace 1–10 |
| `SUPER + G` | Nhóm cửa sổ (komorebi stack) |
| `SUPER + S` | Scratchpad |

Chi tiết + những chỗ **cố tình lệch** khỏi Omarchy (và lý do):
[`docs/keybindings.md`](docs/keybindings.md).

## Cài không cần clone

```powershell
$repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"; irm "$repo/scripts/bootstrap-windows.ps1" | iex
```

AlmaLinux WSL:

```bash
repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo"
```

Xem thêm [`docs/no-clone-install.md`](docs/no-clone-install.md).

> Đường no-clone **copy** config thay vì symlink — symlink sẽ trỏ vào `%TEMP%`
> và biến mất ở lần bootstrap sau. Muốn sửa repo là ăn ngay thì clone rồi chạy
> `link-configs.ps1`.

## Cấu trúc repo

```text
.
├── configs/
│   ├── alacritty/       alacritty.toml + alacritty.wsl.toml
│   ├── komorebi/        komorebi.json
│   ├── whkd/            whkdrc  (keymap Omarchy)
│   ├── yasb/            config.yaml + styles.css
│   ├── powershell/      profile PS7
│   ├── oh-my-posh/      theme prompt
│   ├── git/             gitconfig
│   ├── ssh/             config.example
│   ├── wsl/             .wslconfig, wsl.conf, ssh-agent-bridge.sh
│   ├── tmux/            tmux.conf
│   ├── zsh/             zshrc, aliases.zsh
│   ├── winget/          packages.json  (nguồn app duy nhất)
│   └── lazyvim/
├── docs/
│   ├── keybindings.md            keymap Omarchy + chỗ lệch
│   ├── aliases-and-shell.md
│   ├── ssh-bitwarden-electerm.md agent → WSL
│   ├── jump-server.md
│   ├── workflow.md
│   └── no-clone-install.md
├── scripts/
│   ├── install-windows.ps1       package (đọc packages.json)
│   ├── link-configs.ps1          symlink + backup + autostart
│   ├── start-desktop.ps1
│   ├── doctor.ps1                ✅ verify
│   ├── bootstrap-windows.ps1     đường no-clone
│   ├── install-almalinux.sh
│   ├── bootstrap-almalinux.sh
│   ├── lib/common.ps1            helper dùng chung
│   └── omarchy/                  menu, cheatsheet, scratchpad, stack toggle
└── .github/workflows/validate.yml
```

## doctor.ps1

```powershell
./scripts/doctor.ps1            # config đã cài
./scripts/doctor.ps1 -Repo      # file trong repo
./scripts/doctor.ps1 -Quick     # bỏ qua tra winget (chậm)
```

Nó bắt đúng hai loại lỗi từng làm hỏng setup này và **không hề báo gì** cho tới
khi bạn đăng nhập lại:

- **Tên phím whkd sai.** whkd đẩy từng token vào `VKey::from_keyname`; **một
  tên sai là daemon chết**, kéo theo toàn bộ hotkey — im lặng. `enter` không
  hợp lệ (phải là `return`), `,` không hợp lệ (phải là `oem_comma`).
- **winget id không tồn tại.** `winget install` với id sai chỉ in lỗi rồi đi
  tiếp, nên app đơn giản là không được cài.

CI chạy đúng các kiểm tra đó trên mọi push.

## WSL2

`configs/wsl/.wslconfig` bật `networkingMode=mirrored`, `dnsTunneling`,
`sparseVhd`, `autoMemoryReclaim` và giới hạn RAM/CPU. `configs/wsl/wsl.conf`
bật `systemd` và tắt `appendWindowsPath` (nguyên nhân số một khiến tab-complete
trong WSL chậm, và khiến binary Windows che mất binary Linux).

```bash
sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf
```

```powershell
wsl --shutdown
```

## Ghi công

Layout keybinding và ý tưởng menu port từ
[Omarchy](https://github.com/omacom/omarchy) của DHH / Basecamp (branch
`quattro`), cùng bảng màu Tokyo Night. Omarchy chạy Hyprland trên Arch; đây là
bản diễn dịch sang komorebi + whkd + yasb trên Windows 11.
