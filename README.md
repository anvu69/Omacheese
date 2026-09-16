# Omacheese — Windows 11 developer power-user setup

*[Tiếng Việt](README.vi.md)*

A keyboard-first Windows 11 setup: tiling window manager, terminal-heavy,
Vim/Neovim, WSL2, remote-first — with the navigation and workspace model ported
from [Omarchy](https://omarchy.org).

**Omacheese is this repo's own name for that port.** It is not affiliated with
Omarchy; see [Credits](#credits) for exactly what was borrowed.

## Install

A freshly installed Windows has no `git` to clone with. One line is enough:

```powershell
irm https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/install.ps1 | iex
```

No clone, nothing installed first. It downloads the repo as an archive and runs
the same `setup.ps1` below.

To pass options through `iex`, wrap it in a script block:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/install.ps1))) -Preset desktop -Yes
```

Details, and how to install only part of it: [`docs/no-clone-install.md`](docs/no-clone-install.md).

Already cloned:

```powershell
./scripts/setup.ps1
```

Both routes reach the same TUI: it detects the hardware, offers only the modules
the machine **can actually run**, and reports progress step by step.

```text
+- Modules ---------------------------------------------------------+
| Microsoft Windows 11 Pro  build 26200   32 GB RAM   24 threads     |
| GPU  NVIDIA GeForce RTX 4080 SUPER  16 GB VRAM  CUDA 8.9           |
+-------------------------------------------------------------------+
| > [x] core         PowerShell 7, Alacritty, git, Nerd Font         |
|   [x] wm           komorebi + whkd + yasb (Omarchy keymap)         |
|   [ ] debloat      Win11Debloat + tweaks for tiling                |
|   [-] localllm     Local LLM: vLLM (GPU)                           |
|         also select 'wsl', or re-run after a reboot                |
+-------------------------------------------------------------------+
| 7 selected   space toggle  a all  n none  enter start  q quit      |
+-------------------------------------------------------------------+
```

Non-interactive:

```powershell
./scripts/setup.ps1 -Preset desktop -Yes
./scripts/setup.ps1 -Preset everything -DryRun    # show the plan, change nothing
./scripts/setup.ps1 -Modules core,cli,configs
```

| Preset | Includes |
|---|---|
| `minimal` | terminal, shell, CLI, dotfiles |
| `desktop` | + tiling WM (Omarchy keymap), debloat |
| `full` | + coding agents, WSL2 AlmaLinux |
| `everything` | + local LLM **if the hardware allows** |
| `custom` | pick your own |

When it finishes, press **`SUPER + /`** for every keybinding.

> The TUI runs on **Windows PowerShell 5.1** with zero dependencies — because
> that is all a freshly installed Windows has. CI enforces it.

## The stack

| Area | Choice |
|---|---|
| Terminal | Alacritty |
| Windows shell | PowerShell 7 + Oh My Posh + PSReadLine Vi mode |
| Window manager | komorebi + whkd + yasb |
| Keymap | Omarchy-style (SUPER-first), see `docs/keybindings.md` |
| Terminal multiplexer | tmux |
| Editor | LazyVim / Neovim |
| CLI | fzf, ripgrep, fd, eza, bat, zoxide, delta, lazygit, gh, jq |
| File search | Everything |
| Browser | Brave + Vimium C |
| Linux dev env | WSL2 + AlmaLinux + Zsh + Oh My Zsh |
| Database | DBeaver Community |
| SSH GUI | electerm |
| SSH keys / vault | Bitwarden Desktop SSH Agent (+ a bridge into WSL) |
| Installer | Zero-dependency TUI, hardware detection, progress tracking |
| Coding agents | Claude Code, Codex, Gemini, OpenCode — Omarchy-style manager |
| Local LLM | Ollama (any machine) or vLLM + GPU (when the VRAM is there) |
| Debloat | Win11Debloat, pinned and version-controlled profile |
| Theme | One palette across every tool (Tokyo Night, Catppuccin) |
| Launcher | Optional Raycast integration |

## Philosophy

- Windows 11 is the **host OS**: window manager, browser, file search, GUI tools.
- WSL2 AlmaLinux is the **dev/runtime OS**: shell, tmux, LazyVim, Ansible, CLI.
- Daily SSH goes **Alacritty → WSL2 → tmux → ssh**; electerm for the GUI cases.
- Jump servers use **ProxyJump**, never `ForwardAgent yes`.
- Config lives in Git and installs as symlinks, so an edit takes effect at once.
- **Everything must be verifiable** — `doctor.ps1` and CI check rather than trust.

## Navigation

`SUPER` is the Windows key. One modifier owns window management, and each added
modifier is a consistent extra dimension:

| Keys | Meaning |
|---|---|
| `SUPER` | focus / go to |
| `SUPER + SHIFT` | take the window with you |
| `SUPER + SHIFT + ALT` | send the window there, stay put |
| `SUPER + ALT` | group (stack) |
| `SUPER + CTRL` | toggle a system setting |

Worth learning first:

| Keys | Action |
|---|---|
| `SUPER + /` | Keybinding list (searchable) |
| `SUPER + SPACE` | Omacheese menu |
| `SUPER + CTRL + TAB` | Former workspace (back-and-forth) |
| `SUPER + 1…0` | Workspace 1–10 |
| `SUPER + G` | Group windows (komorebi stack) |
| `SUPER + S` | Scratchpad |
| `SUPER + A` | Launch the default coding agent |
| `SUPER + SHIFT + CTRL + A` | Pick an agent |

Full list, and the places this **deliberately differs** from Omarchy (with
reasons): [`docs/keybindings.md`](docs/keybindings.md).

## Docs

| | |
|---|---|
| [`docs/keybindings.md`](docs/keybindings.md) | The keymap, and where it deviates from Omarchy |
| [`docs/setup-tui.md`](docs/setup-tui.md) | Installer, modules, hardware gating |
| [`docs/theming.md`](docs/theming.md) | One palette for the whole desktop |
| [`docs/raycast.md`](docs/raycast.md) | Optional Raycast script commands |
| [`docs/ai-stack.md`](docs/ai-stack.md) | Coding agents, Docker/GPU, vLLM |
| [`docs/windows-tuning.md`](docs/windows-tuning.md) | Debloat and taskbar |
| [`docs/no-clone-install.md`](docs/no-clone-install.md) | Installing without a clone |
| [`docs/ssh-bitwarden-electerm.md`](docs/ssh-bitwarden-electerm.md) | SSH agent into WSL |
| [`docs/aliases-and-shell.md`](docs/aliases-and-shell.md) | Shell aliases |
| [`docs/workflow.md`](docs/workflow.md) | Daily workflow |
| [`docs/jump-server.md`](docs/jump-server.md) | ProxyJump setup |

## Repo layout

```text
install.ps1              one-command entry point
scripts/
  setup.ps1              TUI installer
  install-windows.ps1    packages (reads configs/winget/packages.json)
  link-configs.ps1       install configs, back up what was there, autostart
  start-desktop.ps1      komorebi + whkd + yasb + the daemons
  doctor.ps1             verify
  debloat-windows.ps1    Win11Debloat wrapper
  install-wsl.ps1        WSL2 + AlmaLinux
  install-localllm.ps1   Ollama or vLLM, by hardware
  lib/                   tui, hardware detection, modules, shared helpers
  omacheese/             menu, scroll daemon, theme, agents, scratchpad
configs/
  theme/                 palettes (tokyo-night, catppuccin)
  komorebi/ yasb/ whkd/  window manager, bar, hotkeys (+ .tmpl for theming)
  alacritty/ powershell/ oh-my-posh/ zsh/ tmux/ lazyvim/
  wsl/ ssh/ git/ ai/ windows/ winget/
raycast/                 Raycast script commands (optional)
docs/
.github/workflows/validate.yml
```

## doctor.ps1

```powershell
./scripts/doctor.ps1            # the installed config
./scripts/doctor.ps1 -Repo      # the files in the repo
./scripts/doctor.ps1 -Quick     # skip the slow winget lookups
```

It catches the two failure modes that have actually broken this setup, both of
which **report nothing** until you next log in:

- **A wrong whkd key name.** whkd pushes every token through
  `VKey::from_keyname`; **one bad name kills the daemon**, and with it every
  hotkey — silently. `enter` is not valid (it is `return`), `,` is not valid
  (it is `oem_comma`).
- **A winget id that does not exist.** `winget install` with a bad id prints an
  error and moves on, so the app simply never arrives.

CI runs those same checks on every push.

## WSL2

`configs/wsl/.wslconfig` enables `networkingMode=mirrored`, `dnsTunneling`,
`sparseVhd`, `autoMemoryReclaim` and caps RAM/CPU. `configs/wsl/wsl.conf`
enables `systemd` and disables `appendWindowsPath` — the number one cause of
slow tab-completion inside WSL, and of Windows binaries shadowing Linux ones.

```bash
sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf
```

```powershell
wsl --shutdown
```

## Credits

The keyboard model, the menu, and the theme palettes come from
**[Omarchy](https://github.com/omacom/omarchy)** by DHH / Basecamp (branch
`quattro`). Omarchy runs Hyprland on Arch Linux; this repo is a reinterpretation
of its ideas on Windows 11 with komorebi + whkd + yasb. It is not affiliated
with, endorsed by, or a port maintained by the Omarchy project.

Borrowed from Omarchy, specifically:

| What | Where it lives here |
|---|---|
| The modifier grammar — SUPER focuses, SHIFT moves, SHIFT+ALT sends silently, ALT groups, CTRL toggles | `configs/whkd/whkdrc` |
| Arrow-key navigation and the "former workspace" toggle | `configs/whkd/whkdrc` |
| Three-magnitude resize on `-` / `=` | `configs/whkd/whkdrc` |
| Window grouping on `SUPER + G` | `omacheese-stack-toggle.ps1` |
| The one nested menu on `SUPER + SPACE` | `omacheese-menu.ps1` |
| The horizontal scrolling strip (Omarchy gets it from hyprscroller) | `omacheese-scroll-daemon.ps1` |
| The agent launcher, from `bin/omarchy-agent` and `bin/omarchy-default-agent` | `omacheese-agent.ps1` |
| Top bar layout and the workspace dot row | `configs/yasb/` |
| Theme palettes, copied **verbatim** from `themes/<name>/colors.toml` | `configs/theme/` |

Where this departs from Omarchy it is on purpose, and
[`docs/keybindings.md`](docs/keybindings.md) says why in each case.

Also built on: [komorebi](https://github.com/LGUG2Z/komorebi) and
[whkd](https://github.com/LGUG2Z/whkd) by LGUG2Z,
[yasb](https://github.com/amnweb/yasb),
[Alacritty](https://github.com/alacritty/alacritty),
[Win11Debloat](https://github.com/Raphire/Win11Debloat),
[Tokyo Night](https://github.com/folke/tokyonight.nvim) and
[Catppuccin](https://github.com/catppuccin/catppuccin).
