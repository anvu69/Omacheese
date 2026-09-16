# Agent panes: watching several agents at once

Running one coding agent is a terminal. Running four is a problem: you cannot
see which one finished, which one is asking a question, and which one has been
sitting idle for ten minutes.

Omarchy's answer is a pair of pane layouts, one set for tmux and one for
[herdr](https://github.com/herdrdev/herdr). This repo ports both, split along
the line the rest of the repo already uses: tmux lives in WSL, herdr runs on
Windows where the agents are installed.

| | tmux (WSL, zsh) | herdr (Windows, PowerShell) |
|---|---|---|
| Editor + agent + terminal | `tdl <ai> [ai2]` | `hdl <ai> [ai2]` |
| Editor / diff / terminal / agent | `tds [ai]` | `hds [ai]` |
| One layout per subdirectory | `tdlm <ai> [ai2]` | `hdlm <ai> [ai2]` |
| N panes, same command | `tsl <n> <cmd>` | `hsl <n> <cmd>` |
| Open it | `SUPER + ALT + ENTER` | `SUPER + CTRL + ENTER` |

`<ai>` is whatever starts the agent: `claude`, `codex`, `gemini`, `opencode`.

## The layouts

`tdl` / `hdl` is the one you will use. Editor on the left at 70%, agent on the
right, a short terminal along the bottom. Pass a second agent and the right
column splits in two, so you can put Claude and Codex on the same problem and
read both answers.

`tdlm` / `hdlm` walks the subdirectories of wherever you are and builds one of
those per project, each in its own window (tmux) or tab (herdr). Point it at a
folder of repos and you get the whole tree, one agent each, switchable with
`ALT+1..9`.

`tsl` / `hsl` tiles N panes and runs the same command in all of them. Same
agent, same tree, N attempts; take whichever answer lands first.

## What herdr adds

tmux does not know what is running inside a pane. herdr does: it watches
whether the process is blocked on input or burning CPU, and marks every pane
working, blocked, done or idle.

```powershell
hstat
```

```text
State   Agent  Pane  Directory  Title
-----   -----  ----  ---------  -----
blocked codex  w1:p5 api        Codex
working claude w1:p3 web        Claude Code
idle    claude w2:p1 infra      Claude Code
```

Blocked sorts first, because that is the one waiting on you. The same list is
in the menu under *Agents > Agent panes (herdr) > Agent status*, and in Raycast
under *Agent Panes*.

Inside a herdr session, `prefix + a` cycles to the next agent and
`prefix + ALT + 1..9` jumps straight to one. The prefix is `CTRL + A`, the same
as this repo's tmux.

herdr also exposes a CLI and a socket API, so an agent in one pane can open
another pane, start a second agent in it, and wait for it:

```powershell
herdr pane split --current --direction right --ratio 0.5
herdr agent wait --state blocked
herdr agent prompt <pane_id> "review the diff in the left pane"
```

## Installing herdr

It is optional and off by default. In the installer TUI, tick `herdr`; or:

```powershell
./scripts/install-herdr.ps1
```

**Not `winget install herdr`.** Searching winget for herdr returns four
packages, and the `herdr` moniker belongs to `hdosys.herdr-win`, an unofficial
third-party fork. `khanhtd36.herdr-khanhtd36` is another fork, relicensed
AGPL-3.0. `hdosys.herdr-sandbox` is a different tool. The only official package
is `Herdr.Herdr.Preview`, which is the preview channel, and herdr's own docs
recommend stable on Windows. So the installer goes to `herdr.dev`, which is
what those docs tell you to run: per-user, no admin, SHA-256 verified.

## Theming

`configs/herdr/config.toml.tmpl` mirrors `configs/tmux/tmux.conf` key for key,
the way Omarchy's herdr config mirrors its own tmux config. The vocabulary maps
across:

```text
tmux session  ->  herdr workspace
tmux window   ->  herdr tab
tmux pane     ->  herdr pane
```

Colours come from the active palette like everything else, so
`omacheese-theme.ps1 -Set catppuccin` moves herdr with the rest of the desktop.
herdr ships built-in `tokyo-night` and `catppuccin` themes, but the template
uses `name = "terminal"` plus explicit overrides instead, so any of Omarchy's
other palettes works the moment you drop its `colors.toml` into
`configs/theme/`.

One trap worth knowing: herdr reads `%APPDATA%\herdr\config.toml`, not
`~/.config/herdr`. `herdr --help` prints the path. `herdr config check` answers
`config: ok` for a file it never opened, so pointing at the wrong path looks
exactly like a working setup. `doctor.ps1` checks the real one.

## Two multiplexers?

Yes, and that is why herdr is opt-in. tmux is already installed inside WSL and
keeps an SSH session alive when the link drops, which is the job it is there
for. herdr is for watching agents on the Windows side. If you only ever run one
agent at a time, you do not need it.

## Credits

Both sets of layouts are ports of Omarchy's `default/bash/fns/tmux` and
`default/bash/fns/herdr`, and the config mirroring idea is theirs too. The
differences are noted in the files: `hunk diff --watch` becomes a `git diff`
loop because hunk has no Windows or AlmaLinux build, and `tdl` focuses the
editor pane rather than an unset variable.
