# Windows 11 Developer Power-User Setup

Combo Windows 11 cho developer theo hướng **keyboard-first, tiling window
manager, terminal-heavy, Vim/Neovim, WSL2, remote-first** — với navigation và
quản lý workspace port từ [Omarchy](https://omarchy.org).

## Cài

```powershell
./scripts/setup.ps1
```

Một lệnh. TUI sẽ dò phần cứng, chỉ hiện module máy bạn **chạy được**, rồi
theo dõi tiến trình từng bước.

```text
+- Modules ---------------------------------------------------------+
| Microsoft Windows 11 Pro  build 26200   32 GB RAM   24 threads     |
| GPU  NVIDIA GeForce RTX 4080 SUPER  16 GB VRAM  CUDA 8.9           |
+-------------------------------------------------------------------+
| > [x] core         PowerShell 7, Alacritty, git, Nerd Font         |
|   [x] wm           komorebi + whkd + yasb (Omarchy keymap)         |
|   [ ] debloat      Win11Debloat + tweaks cho tiling                |
|   [-] localllm     Local LLM: vLLM (GPU)                           |
|         cần chọn 'wsl' nữa, hoặc chạy lại sau khi reboot           |
+-------------------------------------------------------------------+
| 7 selected   space toggle  a all  n none  enter start  q quit      |
+-------------------------------------------------------------------+
```

Không tương tác được thì dùng preset:

```powershell
./scripts/setup.ps1 -Preset desktop -Yes
./scripts/setup.ps1 -Preset everything -DryRun    # xem kế hoạch, không đổi gì
./scripts/setup.ps1 -Modules core,cli,configs
```

| Preset | Gồm |
|---|---|
| `minimal` | terminal, shell, CLI, dotfiles |
| `desktop` | + tiling WM (Omarchy keymap), debloat |
| `full` | + coding agents, WSL2 AlmaLinux |
| `everything` | + local LLM **nếu phần cứng cho phép** |
| `custom` | tự chọn |

Xong rồi bấm **`SUPER + /`** để xem toàn bộ keybinding.

> TUI chạy trên **Windows PowerShell 5.1** với zero dependency — vì đó là tất
> cả những gì một máy Windows vừa cài xong có. CI kiểm tra điều này.

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
| Installer | TUI zero-dependency, dò phần cứng, theo dõi tiến trình |
| Coding agents | Claude Code, Codex, Gemini, OpenCode — manager kiểu Omarchy |
| Local LLM | Ollama (mọi máy) hoặc vLLM + GPU (khi đủ VRAM) |
| Debloat | Win11Debloat, profile pin + version-control |
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
| `SUPER + A` | Mở coding agent mặc định |
| `SUPER + SHIFT + CTRL + A` | Chọn agent |

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
│   ├── windows/         debloat.json   (profile Win11Debloat)
│   ├── ai/              compose vLLM + fine-tune
│   └── lazyvim/
├── raycast/             script commands cho Raycast (tuỳ chọn)
├── docs/
│   ├── setup-tui.md              TUI installer + gating
│   ├── keybindings.md            keymap Omarchy + chỗ lệch
│   ├── ai-stack.md               agents, Docker/GPU, vLLM
│   ├── windows-tuning.md         debloat + taskbar
│   ├── raycast.md                script commands (tuỳ chọn)
│   ├── aliases-and-shell.md
│   ├── ssh-bitwarden-electerm.md agent → WSL
│   ├── jump-server.md
│   ├── workflow.md
│   └── no-clone-install.md
├── scripts/
│   ├── setup.ps1                 ⭐ TUI installer
│   ├── install-windows.ps1       package (đọc packages.json)
│   ├── link-configs.ps1          symlink + backup + autostart
│   ├── start-desktop.ps1
│   ├── doctor.ps1                ✅ verify
│   ├── bootstrap-windows.ps1     đường no-clone
│   ├── debloat-windows.ps1       Win11Debloat wrapper
│   ├── install-wsl.ps1           WSL2 + AlmaLinux
│   ├── install-localllm.ps1      Ollama hoặc vLLM theo phần cứng
│   ├── install-docker-wsl.sh     Docker + NVIDIA toolkit
│   ├── install-almalinux.sh
│   ├── bootstrap-almalinux.sh
│   ├── lib/tui.ps1               TUI (PS 5.1, zero dep)
│   ├── lib/detect.ps1            dò phần cứng
│   ├── lib/modules.ps1           module + gating
│   ├── lib/common.ps1            helper dùng chung
│   └── omarchy/                  menu (GUI), cheatsheet, scroll daemon, agents
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
