# Runtimes and language versions

Two different problems, solved in two places.

## Runtimes: in `core`, because other software assumes them

| | |
|---|---|
| `Microsoft.VCRedist.2015+.x64` / `.arm64` | Visual C++ 2015-2022 runtime, 17 MB |
| `Microsoft.VCRedist.2015+.x86` | 6 MB. Still needed: plenty of developer tooling is 32-bit on a 64-bit machine. |
| `Microsoft.DotNet.DesktopRuntime.10` | 57 MB, runs .NET apps |

These are dependencies, not choices. When they are missing you do not get a
message about a missing runtime - you get some unrelated application failing to
start, which is a much worse afternoon. That is why they are in the required
group.

The VC++ entries are architecture-gated. A package in `packages.json` can carry
an `arch` field, and the installer skips it on a machine of a different
architecture, so an ARM64 machine gets the ARM64 build instead of downloading
an x64 one that does nothing for it.

`doctor.ps1` checks all three by asking the machine, not by assuming:

```text
runtimes and toolchains
  PASS  Visual C++ runtime present (9 entries)
  PASS  .NET runtimes: 14 installed
  PASS  .NET SDK: 2 installed
  PASS  mise 2026.9.5 windows-x64
```

## Language versions: `mise`, in the `langs` module

One binary handles all five, rather than five managers each shimming their own
executable onto PATH and arguing about order:

```powershell
mise use node@22          # in this directory
mise use -g python@3.13   # everywhere
mise ls                   # what is pinned
```

Verified on Windows, not assumed - `mise ls-remote` resolves on every one of
them, and an actual `mise install node@22` finished in 13 seconds and produced
a working `node --version`:

| | versions available on Windows |
|---|---|
| node | 865 |
| python | 125 |
| go | 289 |
| rust | 154 |
| dart | 179 |

Installing mise installs no language. It is 35 MB and sits there until you ask
for something, which is why it can be on by default without costing anyone a
download they did not want.

mise also reads `.tool-versions` and `.mise.toml`, so a repo that pins its
versions gets them automatically when you `cd` into it.

### mise and fnm

`fnm` is still installed by the `agents` module, because the npm-based coding
agents need a node and fnm is 3 MB. Both can manage node, and if you activate
both, whichever is earlier on PATH wins.

Pick one for node. If you want mise to own it, `mise use -g node@lts` and let
fnm just sit there for the agents; if you prefer fnm, do not `mise use node`.
This is a real conflict rather than a theoretical one, which is why it is
written down here.

### Rust

mise can install rust, and that is what the `langs` module gives you. If you
would rather have the canonical toolchain manager, `rustup` is one command
away and the two can coexist as long as only one is on PATH:

```powershell
winget install --id Rustlang.Rustup -e
```

Inside WSL, `install-almalinux.sh` already installs rustup - that side is
unchanged.

## The .NET SDK is separate

`Microsoft.DotNet.SDK.10` is 205 MB, four times the runtime, and only useful if
you actually run `dotnet build`. So it is its own module, on by default in the
`full` and `everything` presets and one untick away:

```powershell
./scripts/setup.ps1 -Modules dotnet
```

The SDK includes the runtime, so installing it makes the core one redundant -
harmless, and it means a machine that only got core can still run .NET apps.

## Upgrading later

The installer **skips** a package that is already installed rather than
upgrading it, so that provisioning a machine does not silently move versions
under someone using it. To upgrade instead:

```powershell
./scripts/install-windows.ps1 -Groups core,langs,dotnet -Force
```

`doctor.ps1` reports when winget has a newer PowerShell than the one installed,
which is the one that matters most here.
