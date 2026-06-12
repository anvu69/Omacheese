# Daily Workflow

## Launching

| Action | Tool |
|---|---|
| Open terminal | Alacritty |
| Manage windows | komorebi + whkd |
| Status bar | yasb |
| Search files | Everything |
| Browser | Brave + Vimium C |
| SSH GUI | electerm |
| DB GUI | DBeaver Community |

## Terminal-first flow

```text
Alacritty -> WSL2 AlmaLinux -> Zsh -> tmux -> LazyVim / ssh / CLI tools
```

## SSH flow

Manual GUI:

```text
electerm -> Bitwarden SSH Agent -> jump server -> target server
```

Terminal:

```text
Alacritty -> WSL2 -> tmux -> ssh host-from-config
```

Fast host picker:

```bash
ss   # fzf host picker, direct ssh
sst  # fzf host picker, opens/reuses tmux session
```

## DB flow

GUI:

```text
DBeaver Community
```

CLI:

```text
pgcli / mycli / litecli
```

## Browser flow

Use Brave + Vimium C:

- `j/k`: scroll
- `f`: open link hints
- `gg/G`: top/bottom
- `t`: new tab
- `x`: close tab
- `X`: restore tab
