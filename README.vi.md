# Omacheese — Windows 11 developer power-user setup

*[English](README.md)*

Combo Windows 11 cho developer theo hướng **keyboard-first, tiling window
manager, terminal-heavy, Vim/Neovim, WSL2, remote-first** — với navigation và
quản lý workspace port từ [Omarchy](https://omarchy.org).

**Omacheese là tên riêng của repo này** cho bản port đó. Nó không liên kết với
dự án Omarchy; xem [Ghi công](#ghi-công) để biết chính xác đã vay mượn những gì.

## Cài

Máy vừa cài Windows xong thì chưa có `git` để clone. Một dòng này là đủ:

```powershell
irm https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/install.ps1 | iex
```

Không cần clone, không cần cài gì trước. Nó tải cả repo dạng zip rồi chạy đúng
`setup.ps1` bên dưới.

Muốn truyền tham số qua `iex` thì bọc lại:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/install.ps1))) -Preset desktop -Yes
```

Chi tiết và cách chỉ-cài-một-phần: [`docs/no-clone-install.md`](docs/no-clone-install.md).

Đã clone rồi thì:

```powershell
./scripts/setup.ps1
```

Cả hai đường đều vào cùng một TUI: dò phần cứng, chỉ hiện module máy bạn **chạy
được**, rồi theo dõi tiến trình từng bước.

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

> TUI chạy trên **Windows PowerShell 5.1** với zero dependency — vì đó là tất cả
> những gì một máy Windows vừa cài xong có. CI kiểm tra điều này.

## Stack chính

| Nhóm | Lựa chọn |
|---|---|
| Terminal | Alacritty |
| Windows shell | PowerShell 7 + Oh My Posh + PSReadLine Vi mode |
| Window manager | komorebi + whkd + yasb |
| Keymap | Kiểu Omarchy (SUPER-first), xem `docs/keybindings.md` |
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
| Theme | Một palette dùng chung mọi tool (Tokyo Night, Catppuccin) |
| Launcher | Raycast (tuỳ chọn) |

## Triết lý

- Windows 11 là **host OS**: window manager, browser, file search, GUI tools.
- WSL2 AlmaLinux là **dev/runtime OS**: shell, tmux, LazyVim, Ansible, CLI.
- SSH daily dùng **Alacritty → WSL2 → tmux → ssh**; electerm cho việc GUI.
- Jump server dùng **ProxyJump**, không dùng `ForwardAgent yes`.
- Config sống trong Git, cài bằng symlink để sửa là ăn ngay.
- **Mọi thứ phải verify được** — `doctor.ps1` và CI kiểm tra thay vì tin tưởng.

## Navigation

`SUPER` là phím Windows. Một modifier quản cửa sổ, mỗi modifier thêm vào là một
chiều nhất quán:

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
| `SUPER + SPACE` | Menu Omacheese |
| `SUPER + CTRL + TAB` | Workspace vừa rồi (back-and-forth) |
| `SUPER + 1…0` | Workspace 1–10 |
| `SUPER + G` | Nhóm cửa sổ (komorebi stack) |
| `SUPER + S` | Scratchpad |
| `SUPER + A` | Mở coding agent mặc định |
| `SUPER + SHIFT + CTRL + A` | Chọn agent |

Chi tiết + những chỗ **cố tình lệch** khỏi Omarchy (và lý do):
[`docs/keybindings.md`](docs/keybindings.md).

## Tài liệu

| | |
|---|---|
| [`docs/keybindings.md`](docs/keybindings.md) | Keymap và chỗ lệch khỏi Omarchy |
| [`docs/setup-tui.md`](docs/setup-tui.md) | Installer, module, gating theo phần cứng |
| [`docs/theming.md`](docs/theming.md) | Một palette cho cả desktop |
| [`docs/raycast.md`](docs/raycast.md) | Script commands cho Raycast (tuỳ chọn) |
| [`docs/ai-stack.md`](docs/ai-stack.md) | Coding agents, Docker/GPU, vLLM |
| [`docs/windows-tuning.md`](docs/windows-tuning.md) | Debloat và taskbar |
| [`docs/no-clone-install.md`](docs/no-clone-install.md) | Cài không cần clone |
| [`docs/ssh-bitwarden-electerm.md`](docs/ssh-bitwarden-electerm.md) | SSH agent vào WSL |
| [`docs/aliases-and-shell.md`](docs/aliases-and-shell.md) | Alias shell |
| [`docs/workflow.md`](docs/workflow.md) | Workflow hằng ngày |
| [`docs/jump-server.md`](docs/jump-server.md) | Cấu hình ProxyJump |

## Cấu trúc repo

```text
install.ps1              điểm vào một lệnh
scripts/
  setup.ps1              TUI installer
  install-windows.ps1    cài app (đọc configs/winget/packages.json)
  link-configs.ps1       cài config, backup cái cũ, autostart
  start-desktop.ps1      komorebi + whkd + yasb + các daemon
  doctor.ps1             kiểm tra
  debloat-windows.ps1    wrapper Win11Debloat
  install-wsl.ps1        WSL2 + AlmaLinux
  install-localllm.ps1   Ollama hoặc vLLM theo phần cứng
  lib/                   tui, dò phần cứng, module, helper chung
  omacheese/             menu, scroll daemon, theme, agents, scratchpad
configs/
  theme/                 palette (tokyo-night, catppuccin)
  komorebi/ yasb/ whkd/  window manager, bar, hotkey (+ .tmpl cho theme)
  alacritty/ powershell/ oh-my-posh/ zsh/ tmux/ lazyvim/
  wsl/ ssh/ git/ ai/ windows/ winget/
raycast/                 Raycast script commands (tuỳ chọn)
docs/
.github/workflows/validate.yml
```

## doctor.ps1

```powershell
./scripts/doctor.ps1            # config đã cài
./scripts/doctor.ps1 -Repo      # file trong repo
./scripts/doctor.ps1 -Quick     # bỏ qua tra winget (chậm)
```

Nó bắt đúng hai loại lỗi từng làm hỏng setup này và **không hề báo gì** cho tới
khi bạn đăng nhập lại:

- **Tên phím whkd sai.** whkd đẩy từng token vào `VKey::from_keyname`; **một tên
  sai là daemon chết**, kéo theo toàn bộ hotkey — im lặng. `enter` không hợp lệ
  (phải là `return`), `,` không hợp lệ (phải là `oem_comma`).
- **winget id không tồn tại.** `winget install` với id sai chỉ in lỗi rồi đi
  tiếp, nên app đơn giản là không được cài.

CI chạy đúng các kiểm tra đó trên mọi push.

## WSL2

`configs/wsl/.wslconfig` bật `networkingMode=mirrored`, `dnsTunneling`,
`sparseVhd`, `autoMemoryReclaim` và giới hạn RAM/CPU. `configs/wsl/wsl.conf` bật
`systemd` và tắt `appendWindowsPath` (nguyên nhân số một khiến tab-complete
trong WSL chậm, và khiến binary Windows che mất binary Linux).

```bash
sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf
```

```powershell
wsl --shutdown
```

## Ghi công

Mô hình bàn phím, ý tưởng menu và các bảng màu đến từ
**[Omarchy](https://github.com/omacom/omarchy)** của DHH / Basecamp (branch
`quattro`). Omarchy chạy Hyprland trên Arch Linux; repo này là bản diễn dịch
những ý tưởng đó sang Windows 11 với komorebi + whkd + yasb. Nó **không** liên
kết, không được bảo trợ, và không phải bản port do dự án Omarchy duy trì.

Cụ thể những gì vay mượn từ Omarchy:

| Cái gì | Nằm ở đâu trong repo này |
|---|---|
| Ngữ pháp modifier — SUPER focus, SHIFT mang theo, SHIFT+ALT gửi đi im lặng, ALT nhóm, CTRL toggle | `configs/whkd/whkdrc` |
| Điều hướng bằng phím mũi tên và toggle "former workspace" | `configs/whkd/whkdrc` |
| Resize ba mức trên `-` / `=` | `configs/whkd/whkdrc` |
| Nhóm cửa sổ bằng `SUPER + G` | `omacheese-stack-toggle.ps1` |
| Một menu lồng nhau duy nhất trên `SUPER + SPACE` | `omacheese-menu.ps1` |
| Chế độ scroll ngang (Omarchy lấy từ hyprscroller) | `omacheese-scroll-daemon.ps1` |
| Agent launcher, từ `bin/omarchy-agent` và `bin/omarchy-default-agent` | `omacheese-agent.ps1` |
| Layout thanh trên cùng và hàng chấm workspace | `configs/yasb/` |
| Bảng màu, copy **nguyên văn** từ `themes/<name>/colors.toml` | `configs/theme/` |

Những chỗ lệch khỏi Omarchy đều là cố ý, và
[`docs/keybindings.md`](docs/keybindings.md) giải thích lý do từng chỗ.

Ngoài ra còn dựa trên: [komorebi](https://github.com/LGUG2Z/komorebi) và
[whkd](https://github.com/LGUG2Z/whkd) của LGUG2Z,
[yasb](https://github.com/amnweb/yasb),
[Alacritty](https://github.com/alacritty/alacritty),
[Win11Debloat](https://github.com/Raphire/Win11Debloat),
[Tokyo Night](https://github.com/folke/tokyonight.nvim) và
[Catppuccin](https://github.com/catppuccin/catppuccin).
