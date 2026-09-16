# Contributing

Bug reports and patches are welcome. This file is mostly about the traps,
because almost every bug this repo has had came from the same two families and
you will save yourself an evening by knowing them first.

## Run the checks before you open a PR

```powershell
./scripts/doctor.ps1 -Repo    # checks the repo's files
./scripts/doctor.ps1          # checks what is installed on this machine
```

CI runs four jobs on every push and they are not decorative - they exist
because each one caught something real. If CI is red, the PR is not ready, even
if the change "obviously works".

## The two ways this project breaks

### 1. Naming something that does not exist

Nothing errors. The name is simply wrong and the feature silently does nothing.
Every one of these has actually shipped here:

| Wrong name | What happened |
|---|---|
| a winget id that does not resolve | `winget install` prints an error, carries on, app never installed |
| a whkd key name like `enter` instead of `return` | whkd refuses to start, **all** hotkeys die, silently |
| a font family that is not installed | Windows substitutes a font with no glyphs, icons become tofu |
| `Fail` where the helper is called `Bad` | the check itself throws, and the branch had never run |
| `snippingtool:` on Windows 11 | protocol not registered, hotkey does nothing |
| `$ctx.RepoRoot` | a field that was never on the context object |
| `-Apply` on a script whose switch is `-Set` | invented parameter |
| `~/.config/herdr/config.toml` | herdr reads `%APPDATA%`, and `herdr config check` says "ok" for a file it never opened |

So: **check the name against the thing**. Run the command. Read `--help`. Print
the object. Do not trust the docs and do not trust your memory. Most of the CI
steps here are a guard against one of the rows above.

### 2. Environment that does not survive the process boundary

A GUI-launched process does not have your shell's PATH. This has bitten the
repo five separate times.

- `start "" alacritty` finds nothing, because installers register neither on
  PATH nor in App Paths. That is why every app hotkey goes through
  `omacheese-open.cmd`.
- A process started before winget installed something still has the old PATH.
  `setup.ps1` refreshes PATH from the registry before every step for this
  reason; `doctor.ps1` rebuilds it at the top so it reports what a fresh login
  would see, not what your terminal happens to have.

## Line endings and encodings

`.gitattributes` pins these. Do not fight it.

- Anything bash or WSL reads must be **LF and BOM-less**. A CRLF `.sh` gives
  `command not found` on a line that looks fine; a BOM gives
  `<BOM>printf: command not found`.
- `Set-Content -Encoding utf8` writes a BOM on Windows PowerShell 5.1 and not
  on 7. For any file WSL will read, use
  `[System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding($false)))`.
- `.cmd` files are CRLF. cmd.exe is unreliable with LF-only multi-line blocks.

## PowerShell: 5.1 is not optional

A fresh Windows 11 has only Windows PowerShell 5.1. `install.ps1` runs there,
calls `setup.ps1` in the same process, and `setup.ps1` spawns every sub-script
with the same host. So **everything under `scripts/` must parse and run on
5.1**, including after the `core` module installs pwsh 7 - the host does not
change mid-run.

That rules out `??`, `?.`, ternaries, `&&`/`||` chains, `ForEach-Object
-Parallel`, `-AsHashtable`, `$IsWindows`, and friends. CI checks both: every
`.ps1` parses under 5.1, and the install path actually runs there with a
timeout, so a script that waits for a key fails instead of hanging.

`irm | iex` has its own trap: it runs the text in the caller's scope, so a
`param()` block declares its variables there. `[ValidateSet]` on a `[string]`
with no default rejects the `""` that `[string]` made from `$null`, and the
script dies before running a line of itself. Validate in the body instead.

## Style

Match what is already there. In particular: **comments say why, not what.** A
comment that restates the code is noise; a comment that records the measurement
or the failure behind a line is why this repo is maintainable. Look at any file
here for the shape.

If you fix a bug, leave the reason in the code. The next person will hit it
too.

## Testing a change

Prefer an actual measurement over an argument. This repo was built by running
the real commands - driving real key events through whkd's hook, diffing files
byte for byte, timing things inside the process, and writing deliberately
broken inputs to confirm a check actually fires. A guard that has never been
seen to fail is not known to work.

## Scope

This targets a **fresh Windows 11 machine**, and it has to work on hardware
very unlike the maintainer's. Two rules follow:

- Anything that needs specific hardware (the local LLM module) must be
  optional, off by default, and must say what it needs.
- Anything that touches a machine's existing apps or configs must back them up
  first, into one folder whose path is printed to the user.

## Licensing

MIT, and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) records what came
from elsewhere. If you add code derived from another project, add it there in
the same PR.
