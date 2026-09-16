# Omacheese

Setup Windows 11 cho developer theo hướng keyboard-first: tiling window manager,
làm việc nhiều trong terminal, Vim/Neovim, WSL2, remote. Phần navigation và quản
lý workspace port từ [Omarchy](https://omarchy.org).

Omacheese là tên riêng của repo này cho bản port đó. Nó không liên kết với dự án
Omarchy. Mục [Ghi công](#ghi-công) liệt kê đã vay mượn những gì và nằm ở đâu.

*[English](README.md)*

## Yêu cầu

- Windows 11 (hoặc Windows 10 build 19041+ nếu muốn dùng WSL2)
- winget, cài qua "App Installer" trên Microsoft Store
- Bật virtualisation trong BIOS, cho module WSL2
- Quyền admin, cho module WSL2 và debloat

Còn lại installer tự lo. Nó chạy trên Windows PowerShell 5.1 không cần module
nào, vì máy Windows vừa cài xong chỉ có bấy nhiêu.

## Cài

Máy mới cài Windows chưa có `git` nên chưa clone được:

```powershell
irm https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/install.ps1 | iex
```

Lệnh này tải cả repo dạng zip rồi chạy `setup.ps1`.

`iex` không nhận tham số. Muốn truyền thì bọc script vào block:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/install.ps1))) -Preset desktop -Yes
```

Nếu đã clone rồi:

```powershell
./scripts/setup.ps1
```

Cả hai đường đều mở cùng một TUI. Nó đọc phần cứng trước rồi làm mờ những module
máy không chạy được, nên bạn không chọn nhầm thứ sẽ chết giữa chừng.

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

Dùng cho CI, phiên remote, hoặc chỗ nào TUI bất tiện:

```powershell
./scripts/setup.ps1 -Preset desktop -Yes
./scripts/setup.ps1 -Preset everything -DryRun    # in kế hoạch ra, không đổi gì
./scripts/setup.ps1 -Modules core,cli,configs
```

| Preset | Gồm |
|---|---|
| `minimal` | terminal, shell, CLI, dotfiles |
| `desktop` | + tiling WM (Omarchy keymap), debloat |
| `full` | + coding agents, WSL2 AlmaLinux |
| `everything` | + local LLM, nếu phần cứng cho phép |
| `custom` | tự chọn |

Module lẻ: `core` `psmodules` `cli` `wm` `desktop` `agents` `raycast` `configs`
`debloat` `wsl` `localllm` `verify`.

Cài một phần, hoặc cài từ fork: [`docs/no-clone-install.md`](docs/no-clone-install.md).

Cài xong, `SUPER + /` liệt kê toàn bộ keybinding.

## Có gì trong đó

| Nhóm | Lựa chọn |
|---|---|
| Terminal | Alacritty |
| Windows shell | PowerShell 7 + Oh My Posh + PSReadLine Vi mode |
| Window manager | komorebi + whkd + yasb |
| Keymap | Kiểu Omarchy, SUPER-first. Xem `docs/keybindings.md` |
| Terminal multiplexer | tmux |
| Editor | LazyVim / Neovim |
| CLI | fzf, ripgrep, fd, eza, bat, zoxide, delta, lazygit, gh, jq |
| File search | Everything |
| Browser | Brave + Vimium C |
| Linux dev env | WSL2 + AlmaLinux + Zsh + Oh My Zsh |
| Database | DBeaver Community |
| SSH GUI | electerm |
| SSH key / vault | Bitwarden Desktop SSH Agent, nối cầu vào WSL |
| Coding agents | Claude Code, Codex, Gemini, OpenCode |
| Local LLM | Ollama cho mọi máy, hoặc vLLM + GPU khi đủ VRAM |
| Debloat | Win11Debloat với profile pin và version-control |
| Theme | Một palette dùng chung mọi tool (Tokyo Night, Catppuccin) |
| Launcher | Raycast, tuỳ chọn |

## Ghép lại thế nào

Windows 11 là host OS, lo window manager, browser, file search và các tool GUI.
WSL2 AlmaLinux là dev/runtime OS, chứa shell, tmux, LazyVim, Ansible và phần
việc CLI.

SSH hằng ngày đi Alacritty vào WSL2 vào tmux rồi ssh, còn electerm dành cho việc
cần GUI. Jump server dùng `ProxyJump`; không bao giờ bật `ForwardAgent yes`, vì
nó phơi agent của bạn ra mọi host bạn nhảy vào.

Config nằm trong Git và cài bằng symlink, nên sửa file trong repo là ăn ngay.
`doctor.ps1` và CI kiểm tra setup thay vì tin là nó chạy.

## Keybinding

`SUPER` là phím Windows. Một modifier lo việc quản cửa sổ, mỗi modifier thêm vào
đổi số phận của cửa sổ đó:

| Phím | Ý nghĩa |
|---|---|
| `SUPER` | focus / đi tới |
| `SUPER + SHIFT` | mang cửa sổ theo |
| `SUPER + SHIFT + ALT` | gửi cửa sổ đi, mình ở lại |
| `SUPER + ALT` | nhóm (stack) |
| `SUPER + CTRL` | toggle hệ thống |

Vài phím nên nhớ trước:

| Phím | Việc |
|---|---|
| `SUPER + /` | Bảng keybinding, search được |
| `SUPER + SPACE` | Menu Omacheese |
| `SUPER + CTRL + TAB` | Workspace vừa rồi, qua lại |
| `SUPER + 1…0` | Workspace 1–10 |
| `SUPER + G` | Nhóm cửa sổ (komorebi stack) |
| `SUPER + S` | Scratchpad |
| `SUPER + A` | Mở coding agent mặc định |
| `SUPER + SHIFT + CTRL + A` | Chọn agent |

Danh sách đầy đủ và những chỗ cố tình lệch khỏi Omarchy nằm trong
[`docs/keybindings.md`](docs/keybindings.md).

## Theme

Một palette chi phối viền komorebi, thanh yasb, Alacritty, menu và Raycast:

```powershell
./scripts/omacheese/omacheese-theme.ps1 -List
./scripts/omacheese/omacheese-theme.ps1 -Set catppuccin
```

Palette chính là file `colors.toml` của Omarchy, nên bất kỳ theme nào của họ
cũng thả vào `configs/theme/` là dùng được luôn. Xem
[`docs/theming.md`](docs/theming.md).

## Khi có sự cố

```powershell
./scripts/doctor.ps1            # kiểm tra config đã cài
./scripts/doctor.ps1 -Repo      # kiểm tra file trong repo
./scripts/doctor.ps1 -Quick     # bỏ qua phần tra winget cho nhanh
```

Nó tồn tại vì hai lỗi đã thật sự xảy ra ở đây, và cả hai đều không báo gì lúc
đó. Bạn chỉ biết khi đăng nhập lại:

Sai tên phím whkd. whkd đẩy từng token qua `VKey::from_keyname`, một tên sai là
daemon chết kéo theo toàn bộ hotkey, im lặng. `enter` không phải tên hợp lệ, phải
là `return`. `,` cũng không, phải là `oem_comma`.

winget id không tồn tại. `winget install` với id sai chỉ in lỗi rồi đi tiếp, nên
app đơn giản là không được cài.

CI chạy đúng hai kiểm tra đó trên mọi lần push.

## WSL2

`configs/wsl/.wslconfig` bật `networkingMode=mirrored`, `dnsTunneling`,
`sparseVhd`, `autoMemoryReclaim` và giới hạn RAM, CPU. `configs/wsl/wsl.conf`
bật `systemd` và tắt `appendWindowsPath`, thủ phạm quen thuộc khiến
tab-completion trong WSL chậm và binary Windows che mất binary Linux.

```bash
sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf
```

```powershell
wsl --shutdown
```

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

## Ghi công

Mô hình bàn phím, ý tưởng menu và các bảng màu đến từ
[Omarchy](https://github.com/omacom/omarchy) của DHH / Basecamp, branch
`quattro`. Omarchy chạy Hyprland trên Arch Linux. Repo này làm lại những ý tưởng
đó cho Windows 11 trên komorebi, whkd và yasb. Nó không liên kết, không được bảo
trợ, và không do dự án Omarchy duy trì.

Vay mượn cái gì, và nằm ở đâu:

| Từ Omarchy | Ở đây |
|---|---|
| Ngữ pháp modifier: SUPER focus, SHIFT mang theo, SHIFT+ALT gửi đi im lặng, ALT nhóm, CTRL toggle | `configs/whkd/whkdrc` |
| Điều hướng bằng phím mũi tên và toggle "former workspace" | `configs/whkd/whkdrc` |
| Resize ba mức trên `-` / `=` | `configs/whkd/whkdrc` |
| Nhóm cửa sổ bằng `SUPER + G` | `omacheese-stack-toggle.ps1` |
| Menu lồng nhau duy nhất trên `SUPER + SPACE` | `omacheese-menu.ps1` |
| Chế độ scroll ngang, thứ Omarchy lấy từ hyprscroller | `omacheese-scroll-daemon.ps1` |
| Agent launcher, từ `bin/omarchy-agent` và `bin/omarchy-default-agent` | `omacheese-agent.ps1` |
| Layout thanh trên cùng và hàng chấm workspace | `configs/yasb/` |
| Bảng màu, copy nguyên văn từ `themes/<name>/colors.toml` | `configs/theme/` |

Những chỗ lệch khỏi Omarchy đều là cố ý, và
[`docs/keybindings.md`](docs/keybindings.md) giải thích lý do từng chỗ.

Ngoài ra còn dựa trên [komorebi](https://github.com/LGUG2Z/komorebi) và
[whkd](https://github.com/LGUG2Z/whkd) của LGUG2Z,
[yasb](https://github.com/amnweb/yasb),
[Alacritty](https://github.com/alacritty/alacritty),
[Win11Debloat](https://github.com/Raphire/Win11Debloat),
[Tokyo Night](https://github.com/folke/tokyonight.nvim) và
[Catppuccin](https://github.com/catppuccin/catppuccin).
