# Third-party notices

This project is MIT licensed (see [LICENSE](LICENSE)). It also contains material
copied from, or derived from, other projects. MIT requires their copyright
notices to travel with that material, so they are reproduced here.

Nothing below is a dependency you have to install separately. These are files
in this repository, or code in this repository, that came from somewhere else.

## Omarchy

<https://github.com/omacom/omarchy>, branch `quattro`, by David Heinemeier
Hansson. MIT licensed.

**Copied verbatim:**

| File here | From |
|---|---|
| `configs/theme/tokyo-night.toml` | `themes/tokyo-night/colors.toml` |
| `configs/theme/catppuccin.toml` | `themes/catppuccin/colors.toml` |

These two are byte-identical to upstream. That is deliberate: it means any of
Omarchy's other palettes can be dropped into `configs/theme/` and used as is.

**Ported, not copied** - rewritten for Windows, PowerShell and komorebi, but
the design is theirs:

| Here | From |
|---|---|
| `configs/whkd/whkdrc` - the modifier grammar and workspace model | `default/hypr/bindings/` |
| `scripts/omacheese/omacheese-agent.ps1` | `bin/omarchy-agent`, `bin/omarchy-default-agent` |
| `scripts/omacheese/omacheese-menu.ps1` - the single nested menu | `default/omarchy/omarchy-menu.jsonc` |
| `configs/zsh/agent-layouts.zsh` - `tdl` / `tds` / `tdlm` / `tsl` | `default/bash/fns/tmux` |
| `configs/powershell/agent-layouts.ps1` - `hdl` / `hds` / `hdlm` / `hsl` | `default/bash/fns/herdr` |
| `configs/herdr/config.toml.tmpl` - mirroring the herdr config onto the tmux config | `config/herdr/config.toml` |

### Omarchy's license

```
Copyright (c) David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

This project is not affiliated with, endorsed by, or maintained by Omarchy.
It is named Omacheese here to keep the two apart.

## Installed, not included

These are installed by the setup and are not redistributed in this repository.
Their licenses apply to them, not to this project, and are listed so you know
what a full install pulls in.

Each line below was read from the project's own licence file, not guessed.

| Tool | License |
|---|---|
| [komorebi](https://github.com/LGUG2Z/komorebi) | Komorebi License 2.0 - a custom source-available licence, not OSI-approved. Read it before any commercial use. |
| [whkd](https://github.com/LGUG2Z/whkd) | Komorebi License 2.0, same as above |
| [yasb](https://github.com/amnweb/yasb) | MIT |
| [Alacritty](https://github.com/alacritty/alacritty) | Apache-2.0 |
| [herdr](https://github.com/herdrdev/herdr) (optional) | Apache-2.0 |
| [Win11Debloat](https://github.com/Raphire/Win11Debloat) | MIT |
| [Oh My Posh](https://github.com/JanDeDobbeleer/oh-my-posh) | MIT |
| [Tokyo Night](https://github.com/folke/tokyonight.nvim) | Apache-2.0 |
| [Catppuccin](https://github.com/catppuccin/catppuccin) | MIT |

The komorebi line matters more than the rest: this repo's whole window manager
is komorebi and whkd, and they are the only two things here that are not under
a standard open-source licence. That is upstream's choice and this project does
not redistribute them - the installer fetches them from winget - but if you are
putting this on a work machine, read their terms first.

If you spot something here that is wrong or missing, please open an issue -
attribution errors are worth fixing quickly.
