# Omacheese

A keyboard-first Windows 11 dev setup: tiling window manager, terminal-heavy,
Vim/Neovim, WSL2, remote work. The navigation and workspace model is ported from
[Omarchy](https://omarchy.org).

Omacheese is this repo's name for that port. It is not affiliated with the
Omarchy project. [Credits](#credits) lists what was borrowed and where it lives.

*[Tiếng Việt](README.vi.md)*

## Requirements

- Windows 11 (or Windows 10 build 19041+ if you want WSL2)
- winget, which ships as "App Installer" from the Microsoft Store
- Virtualisation enabled in the BIOS, for the WSL2 module
- Admin rights, for the WSL2 and debloat modules

Everything else the installer brings in itself. It runs on Windows PowerShell
5.1 with no modules, since that is all a fresh Windows has.

## Install

A fresh Windows has no `git`, so there is nothing to clone with yet:

```powershell
irm https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/install.ps1 | iex
```

That downloads the repo as an archive and runs `setup.ps1`.

`iex` cannot take parameters. To pass any, wrap the script in a block:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/install.ps1))) -Preset desktop -Yes
```

If you already cloned:

```powershell
./scripts/setup.ps1
```

Both routes open the same TUI. It reads the hardware first and greys out
anything the machine cannot run, so you never pick a module that will fail
halfway through.

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

For CI, remote sessions, or anywhere a TUI is awkward:

```powershell
./scripts/setup.ps1 -Preset desktop -Yes
./scripts/setup.ps1 -Preset everything -DryRun    # print the plan, change nothing
./scripts/setup.ps1 -Modules core,cli,configs
```

| Preset | Includes |
|---|---|
| `minimal` | terminal, shell, CLI, dotfiles |
| `desktop` | + tiling WM (Omarchy keymap), debloat |
| `full` | + coding agents, WSL2 AlmaLinux |
| `everything` | + local LLM, if the hardware allows |
| `custom` | pick your own |

Individual modules: `core` `psmodules` `cli` `wm` `desktop` `agents` `raycast`
`configs` `debloat` `wsl` `localllm` `herdr` `verify`.

Installing only part of it, or from a fork:
[`docs/no-clone-install.md`](docs/no-clone-install.md).

Once it finishes, `SUPER + /` lists every keybinding.

## What you get

| Area | Choice |
|---|---|
| Terminal | Alacritty |
| Windows shell | PowerShell 7 + Oh My Posh + PSReadLine Vi mode |
| Window manager | komorebi + whkd + yasb |
| Keymap | Omarchy-style, SUPER-first. See `docs/keybindings.md` |
| Terminal multiplexer | tmux |
| Editor | LazyVim / Neovim |
| CLI | fzf, ripgrep, fd, eza, bat, zoxide, delta, lazygit, gh, jq |
| File search | Everything |
| Browser | Brave + Vimium C |
| Linux dev env | WSL2 + AlmaLinux + Zsh + Oh My Zsh |
| Database | DBeaver Community |
| SSH GUI | electerm |
| SSH keys / vault | Bitwarden Desktop SSH Agent, bridged into WSL |
| Coding agents | Claude Code, Codex, Gemini, OpenCode |
| Agent panes | tmux layouts in WSL; herdr on Windows, optional |
| Local LLM | Ollama anywhere, or vLLM + GPU when the VRAM is there |
| Debloat | Win11Debloat with a pinned, version-controlled profile |
| Theme | One palette across every tool (Tokyo Night, Catppuccin) |
| Launcher | Raycast, optional |

## How it is put together

Windows 11 is the host OS and handles the window manager, browser, file search
and GUI tools. WSL2 AlmaLinux is the dev and runtime OS, with the shell, tmux,
LazyVim, Ansible and the CLI work.

Daily SSH goes Alacritty to WSL2 to tmux to ssh, with electerm for the cases
that want a GUI. Jump servers use `ProxyJump`; `ForwardAgent yes` is never set,
since it exposes your agent to every host you land on.

Config lives in Git and installs as symlinks, so editing a file in the repo
takes effect immediately. `doctor.ps1` and CI check the setup instead of
assuming it works.

## Keybindings

`SUPER` is the Windows key. One modifier handles window management, and each
extra modifier changes what happens to the window:

| Keys | Meaning |
|---|---|
| `SUPER` | focus / go to |
| `SUPER + SHIFT` | take the window with you |
| `SUPER + SHIFT + ALT` | send the window there, stay put |
| `SUPER + ALT` | group (stack) |
| `SUPER + CTRL` | toggle a system setting |

The ones worth learning first:

| Keys | Action |
|---|---|
| `SUPER + /` | Keybinding list, searchable |
| `SUPER + SPACE` | Omacheese menu |
| `SUPER + CTRL + TAB` | Former workspace, back and forth |
| `SUPER + 1…0` | Workspace 1–10 |
| `SUPER + G` | Group windows (komorebi stack) |
| `SUPER + S` | Scratchpad |
| `SUPER + A` | Launch the default coding agent |
| `SUPER + SHIFT + CTRL + A` | Pick an agent |
| `SUPER + ALT + ENTER` | WSL + tmux |
| `SUPER + CTRL + ENTER` | herdr, for watching several agents at once |

The full list, and the places this differs from Omarchy on purpose, are in
[`docs/keybindings.md`](docs/keybindings.md).

## Theming

One palette drives komorebi's borders, the yasb bar, Alacritty, the menu and
Raycast:

```powershell
./scripts/omacheese/omacheese-theme.ps1 -List
./scripts/omacheese/omacheese-theme.ps1 -Set catppuccin
```

Palettes are Omarchy's own `colors.toml` files, so any of its themes can be
dropped into `configs/theme/` and used as is. See
[`docs/theming.md`](docs/theming.md).

## Troubleshooting

```powershell
./scripts/doctor.ps1            # check the installed config
./scripts/doctor.ps1 -Repo      # check the files in the repo
./scripts/doctor.ps1 -Quick     # skip the slow winget lookups
```

It exists because of two failures that have actually happened here, and neither
one reports an error at the time. You find out when you next log in:

A wrong whkd key name. whkd pushes every token through `VKey::from_keyname`, and
one bad name kills the daemon along with every hotkey, silently. `enter` is not
a valid name, it is `return`. `,` is not valid either, it is `oem_comma`.

A winget id that does not exist. `winget install` with a bad id prints an error
and carries on, so the app simply never gets installed.

CI runs the same two checks on every push.

## WSL2

`configs/wsl/.wslconfig` turns on `networkingMode=mirrored`, `dnsTunneling`,
`sparseVhd` and `autoMemoryReclaim`, and caps RAM and CPU. `configs/wsl/wsl.conf`
turns on `systemd` and turns off `appendWindowsPath`, which is the usual reason
tab-completion inside WSL is slow and Windows binaries shadow Linux ones.

```bash
sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf
```

```powershell
wsl --shutdown
```

## Docs

| | |
|---|---|
| [`docs/keybindings.md`](docs/keybindings.md) | The keymap, and where it deviates from Omarchy |
| [`docs/setup-tui.md`](docs/setup-tui.md) | Installer, modules, hardware gating |
| [`docs/theming.md`](docs/theming.md) | One palette for the whole desktop |
| [`docs/raycast.md`](docs/raycast.md) | Optional Raycast script commands |
| [`docs/agent-panes.md`](docs/agent-panes.md) | Running several agents side by side |
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

## Credits

The keyboard model, the menu and the theme palettes come from
[Omarchy](https://github.com/omacom/omarchy) by DHH / Basecamp, branch
`quattro`. Omarchy runs Hyprland on Arch Linux. This repo reworks those ideas
for Windows 11 on komorebi, whkd and yasb. It is not affiliated with, endorsed
by, or maintained by the Omarchy project.

What was borrowed, and where it ended up:

| From Omarchy | Here |
|---|---|
| The modifier grammar: SUPER focuses, SHIFT moves, SHIFT+ALT sends silently, ALT groups, CTRL toggles | `configs/whkd/whkdrc` |
| Arrow-key navigation and the "former workspace" toggle | `configs/whkd/whkdrc` |
| Three-magnitude resize on `-` / `=` | `configs/whkd/whkdrc` |
| Window grouping on `SUPER + G` | `omacheese-stack-toggle.ps1` |
| The single nested menu on `SUPER + SPACE` | `omacheese-menu.ps1` |
| The horizontal scrolling strip, which Omarchy gets from hyprscroller | `omacheese-scroll-daemon.ps1` |
| The agent launcher, from `bin/omarchy-agent` and `bin/omarchy-default-agent` | `omacheese-agent.ps1` |
| The `tdl`/`tds`/`tdlm`/`tsl` and `hdl`/`hds`/`hdlm`/`hsl` pane layouts, from `default/bash/fns/tmux` and `fns/herdr` | `configs/zsh/agent-layouts.zsh`, `configs/powershell/agent-layouts.ps1` |
| Mirroring the herdr config onto the tmux config, and the `SUPER+CTRL+ENTER` chord | `configs/herdr/config.toml.tmpl` |
| Top bar layout and the workspace dot row | `configs/yasb/` |
| Theme palettes, copied verbatim from `themes/<name>/colors.toml` | `configs/theme/` |

Where this departs from Omarchy it is deliberate, and
[`docs/keybindings.md`](docs/keybindings.md) gives the reason in each case.

Also built on [komorebi](https://github.com/LGUG2Z/komorebi) and
[whkd](https://github.com/LGUG2Z/whkd) by LGUG2Z,
[yasb](https://github.com/amnweb/yasb),
[Alacritty](https://github.com/alacritty/alacritty),
[Win11Debloat](https://github.com/Raphire/Win11Debloat),
[Tokyo Night](https://github.com/folke/tokyonight.nvim) and
[Catppuccin](https://github.com/catppuccin/catppuccin).
