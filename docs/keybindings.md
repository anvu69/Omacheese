# Keybindings — Omarchy on Windows

Ported from [Omarchy](https://omarchy.org) (`omacom/omarchy`, branch `quattro`),
`default/hypr/bindings/{tiling,applications,utilities}.lua`.

Press **`SUPER + /`** at any time for a searchable version of this list — it is
generated from the live `whkdrc`, so it can never drift from what is actually
bound.

`SUPER` is the **Windows key**.

---

## The idea

Omarchy's layout is worth copying because it is systematic rather than
historical. One modifier owns window management, and each extra modifier adds
one consistent dimension:

| Modifier | Means |
|---|---|
| `SUPER` | focus / go to |
| `SUPER + SHIFT` | move the window with me |
| `SUPER + SHIFT + ALT` | send the window there, but stay put |
| `SUPER + ALT` | group (stack) operations |
| `SUPER + CTRL` | system toggles |
| `ALT` | cycle windows (classic Alt+Tab) |

Once that clicks you can guess bindings you have never used.

---

## Navigation

| Keys | Action |
|---|---|
| `SUPER + ←↓↑→` | Focus window in that direction |
| `ALT + TAB` | Cycle windows on this workspace |
| `ALT + SHIFT + TAB` | Cycle backwards |
| `SUPER + SHIFT + ←↓↑→` | Swap window in that direction |
| `SUPER + P` | Promote window to the main position |
| `SUPER + SHIFT + P` | Focus the main window |

## Workspaces

| Keys | Action |
|---|---|
| `SUPER + 1…9, 0` | Focus workspace 1–10 |
| `SUPER + SHIFT + 1…0` | Move window there **and follow** |
| `SUPER + SHIFT + ALT + 1…0` | Send window there, **stay where you are** |
| `SUPER + TAB` | Next workspace |
| `SUPER + SHIFT + TAB` | Previous workspace |
| `SUPER + CTRL + TAB` | **Last workspace** (back-and-forth) |
| `SUPER + CTRL + SHIFT + TAB` | Next empty workspace |
| `SUPER + S` / `SUPER + \`` | Scratchpad (press again to return) |
| `SUPER + ALT + S` | Send window to the scratchpad |

`SUPER + CTRL + TAB` is the one to learn first. Omarchy calls it "former
workspace"; it is the alt-tab of workspaces and ends up carrying most of a day.

The scratchpad is workspace 10. Hyprland has a real special workspace and
komorebi does not, so `omarchy-scratchpad.ps1` reads `komorebic state` and
toggles between workspace 10 and wherever you were.

## Monitors

| Keys | Action |
|---|---|
| `CTRL + ALT + TAB` | Focus next monitor |
| `SUPER + ,` / `SUPER + .` | Focus previous / next monitor |
| `SUPER + SHIFT + ,` / `.` | Move window to previous / next monitor |
| `SUPER + SHIFT + ALT + ← →` | Move this whole workspace to another monitor |

## Grouping (stacks)

Omarchy's `SUPER + G` window grouping maps onto komorebi stacks.

| Keys | Action |
|---|---|
| `SUPER + G` | Toggle grouping for the focused window |
| `SUPER + ALT + ←↓↑→` | Pull the neighbour in that direction into the group |
| `SUPER + ALT + G` | Remove window from the group |
| `SUPER + ALT + TAB` | Next window in the group |
| `SUPER + CTRL + ← →` | Previous / next in the group |
| `SUPER + ALT + 1…5` | Jump to group member 1–5 |

## Window state

| Keys | Action |
|---|---|
| `SUPER + W` / `SUPER + Q` | Close |
| `SUPER + SHIFT + Q` | Minimise |
| `SUPER + T` | Toggle floating |
| `SUPER + F` | Maximise |
| `SUPER + CTRL + F` | Monocle (tiled fullscreen) |
| `SUPER + O` | Float override |
| `SUPER + SHIFT + SPACE` | Switch tiling ⇄ floating layer |

## Layout

| Keys | Action |
|---|---|
| `SUPER + SHIFT + L` | Next layout |
| `SUPER + SHIFT + ALT + L` | Previous layout |
| `SUPER + J` | Flip layout horizontally |
| `SUPER + SHIFT + J` | Flip layout vertically |
| `SUPER + CTRL + S` | **Scrolling mode** (see below) |
| `SUPER + R` | Retile |
| `SUPER + SHIFT + R` | Reload komorebi config |
| `SUPER + CTRL + P` | Pause tiling |

## Scrolling mode

`SUPER + CTRL + S`

Omarchy has a mode (via hyprscroller) where windows sit in one horizontal
strip: the focused window takes almost the whole screen and the rest wait just
off the edge, so you scroll sideways instead of splitting the screen smaller
and smaller.

komorebi has this natively as the `scrolling` layout. Two settings give it the
Omarchy shape, and `omarchy-scrolling.ps1` applies both:

```
komorebic change-layout scrolling
komorebic scrolling-layout-columns 1   one window per screen
komorebic workspace-padding 0 <ws> 40  pulls it in so the neighbour peeks
```

Measured on a 2560px monitor:

| Workspace padding | Window width | Neighbour peek |
|---|---|---|
| 8 | 2530 px (98.8%) | none |
| **40** | **2466 px (96.3%)** | **33 px** |
| 70 | 2406 px (94.0%) | 63 px |

40 is the default: about 96% with a visible sliver of what is behind you.
Press the binding again to return to BSP. `SUPER + SPACE` -> Windows has a
two-column variant.

Tune it by editing the defaults in `scripts/omarchy/omarchy-scrolling.ps1`.

## Resize

Omarchy's three-magnitude resize on the `-` / `=` keys.

| Keys | Step |
|---|---|
| `SUPER + -` / `=` | 100 px, horizontal |
| `SUPER + SHIFT + -` / `=` | 100 px, vertical |
| `SUPER + ALT + -` / `=` | 25 px (fine) |
| `SUPER + CTRL + -` / `=` | 300 px (coarse) |

## Applications

| Keys | App |
|---|---|
| `SUPER + ENTER` | Alacritty |
| `SUPER + ALT + ENTER` | Alacritty → WSL → tmux |
| `SUPER + SHIFT + ENTER` / `SUPER + SHIFT + B` | Brave |
| `SUPER + SHIFT + ALT + B` | Brave (private) |
| `SUPER + SHIFT + F` | Explorer |
| `SUPER + SHIFT + E` | Everything |
| `SUPER + SHIFT + N` | Neovim (WSL) |
| `SUPER + SHIFT + G` | electerm |
| `SUPER + SHIFT + D` | DBeaver |
| `SUPER + SHIFT + T` | btop |
| `SUPER + SHIFT + /` | Bitwarden |

## Menus and system

| Keys | Action |
|---|---|
| `SUPER + /` | **Keybindings** (searchable) |
| `SUPER + SPACE` | Omarchy menu |
| `SUPER + ESC` | System menu |
| `SUPER + CTRL + L` | Lock |
| `SUPER + CTRL + B` | Toggle the bar |
| `SUPER + CTRL + R` | Restart the desktop stack |
| `SUPER + PRTSC` | Screen clip |
| `SUPER + SHIFT + ALT + P` | Pause **all** hotkeys (games, RDP) |

---

## Where this deviates from Omarchy, and why

Three bindings could not be copied literally.

**`SUPER + L` is not "toggle layout".** On Windows, `Win+L` locks the session
and is handled on the secure desktop — no hotkey daemon can intercept it, whkd
included. Layout cycling moved to `SUPER + SHIFT + L`; locking stays on
`SUPER + CTRL + L`, as in Omarchy.

**`SUPER + K` is not the cheatsheet; `SUPER + /` is.** `/` reads as "help" and
leaves `K` free.

**No `hjkl` focus by default.** Omarchy navigates with arrow keys and has no
`hjkl` bindings at all. On Windows there is no room to add them: `SUPER + J` is
flip-layout, and `SUPER + L` is unreachable. There is a commented-out Vim
overlay at the bottom of `configs/whkd/whkdrc` that trades those away if you
want it.

## Editing bindings

Edit `configs/whkd/whkdrc`, then:

```powershell
./scripts/doctor.ps1        # validate before you find out the hard way
komorebic reload-configuration
```

> **Key names are not literal.** whkd passes each token to
> `VKey::from_keyname`, and **one bad name aborts the whole daemon** — so every
> hotkey stops working at once, with no error unless you started whkd from a
> terminal. Use `return` (not `enter`), `oem_comma` (not `,`), `oem_minus`
> (not `-`), `oem_plus` (not `=`), `oem_3` (not `` ` ``), `oem_2` (not `/`).
>
> `doctor.ps1` checks every key name and reports duplicate chords. CI runs the
> same check on every push.
