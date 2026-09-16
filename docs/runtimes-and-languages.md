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

## Language versions: mise, and only mise

One binary handles every language, and the coding agents too. This is the model
Omarchy uses - it installs each agent through mise rather than through npm - and
the reason to copy it is that five version managers each shimming their own
executable onto PATH is a fight nobody wins.

```powershell
mise use -g node@lts       # globally
mise use python@3.13       # just this directory, written to .mise.toml
mise ls                    # what is installed
mise up                    # upgrade everything
```

`mise use` writes the version into a config file, so the next person to clone
the repo gets the same one. `mise install` only downloads.

### Quick install

```powershell
# the whole module (this is what the installer does)
./scripts/install-windows.ps1 -Groups langs

# or just mise, by hand
winget install --id jdx.mise -e

# then, in a new terminal: languages
mise use -g node@lts python@3.13 go@latest rust@latest dart@latest

# and the package managers you want on top
mise use -g pnpm yarn bun deno
```

Inside WSL:

```bash
curl -fsSL https://mise.run | sh
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
mise use -g node@lts python@3.13 go@latest rust@latest
```

The Linux side has fewer sharp edges, but not none - see the table below for
which of these actually install where.

### Verified on Windows, not assumed

mise's own docs only promise that support "varies by platform", so every row
below was installed and run on this machine, mise 2026.9.5. Nothing here is
copied from a registry listing.

| language | backend | install | reports |
|---|---|---|---|
| node | `core` | 13s | `v22.23.2` |
| go | `core` | 25s | `go1.27.1 windows/amd64` |
| rust | `core` | 72s | `rustc 1.98.1` |
| java | `core` | 22s | `openjdk 27` |
| ruby | `core` | 19s | `ruby 4.0.7 [x64-mingw-ucrt]` |
| zig | `core` | 102s | `0.16.0` |
| deno | `core` | 13s | `2.9.6` |
| bun | `core` | 10s | `1.4.2` |
| python | `core` | 19s | `3.13.15` |
| dart | `http` | 50s | `Dart SDK 3.13.4` |
| flutter | `http` | 364s | `Flutter 3.47.4 • stable` |
| kotlin | `github` | 23s | `kotlinc-jvm 2.4.20` |
| **php** | `vfox` | **fails** | `post_install.lua:79: Failed to run buildconf` |
| **lua** | `vfox` | **fails** | `Failed to build Lua: make failed` |

The two failures say exactly what is wrong: a `vfox` plugin builds from source,
and that wants a Unix toolchain. Nothing about the language is the problem - PHP
and Lua install fine inside WSL. On Windows, take them from winget instead.

Each language brings its own package manager, so there is nothing else to
install:

| `mise use -g ...` | measured |
|---|---|
| `rust` | `cargo 1.98.1` |
| `go` | `go env GOMODCACHE` answers |
| `java` | `jar 27` |
| `ruby` | `gem 4.0.20` |
| `node` | `npm`, `npx` |

### Alternative package managers

The ones that are separate tools, rather than shipping with the language:

```powershell
mise use -g pnpm yarn bun deno    # node ecosystem
mise use -g uv                    # python
```

### What works on Windows, and how to tell in advance

Not everything does, and the predictor is the **backend**, not the tool. Run
`mise registry <tool>` and read what comes back:

| backend | what it does | Windows |
|---|---|---|
| `core:` | built into mise | works |
| `aqua:` | downloads a prebuilt binary | works, **if** the upstream aqua entry declares Windows |
| `ubi:`, `github:` | downloads a release asset | usually works |
| `npm:` | resolves an npm package | fails when the package compiles native code |
| `vfox:`, `asdf:` | runs a plugin script that builds from source | fails on Windows: measured on php, lua and poetry |

Measured on mise 2026.9.5, this machine:

| tool | backend | result |
|---|---|---|
| pnpm | `aqua` | 15s, 12.4.2 |
| yarn | `aqua` | 8s, 4.18.0 |
| bun | `core` | 10s, 1.4.2 |
| deno | `core` | 13s, 2.9.6 |
| uv | `aqua` | 15s, 0.12.15 |
| pipx | `aqua:pypa/pipx` | **fails**: `unsupported env: windows/amd64 (supported: ["darwin", "linux"])` |
| poetry | `vfox` | **fails**: vfox plugin error |

So an `aqua` backend is not a guarantee on its own - pipx has one and still
refuses, because the upstream registry entry only lists macOS and Linux. The
error is at least explicit about it, which is more than the npm backend manages.

And the same two, measured inside AlmaLinux (mise 2026.9.9) rather than assumed
to be fine because it is Linux:

| tool | inside WSL |
|---|---|
| pipx | **works**, 1s, 1.17.2 - but only after a modern Python exists. On the stock AlmaLinux 3.9 it installs and then refuses to run: `Python 3.10 or later is required`. `mise use -g python@3.13` first and it is fine. |
| poetry | **fails here too**: `Installing Poetry (2.4.3): An error occurred.` A newer Python does not help. The `vfox` backend is the problem, not the platform. |

Which is worth spelling out because the obvious guess - that these are Windows
problems and Linux is fine - is only half right.

### pipx and poetry on Windows: use uv

Both of their jobs are covered by `uv`, which does install cleanly here:

```powershell
uv tool install ruff          # what pipx does - isolated CLI tools
uv tool run ruff check .      # or: uvx ruff check .
uv python install 3.13        # what pyenv does
uv init / uv add / uv sync    # what poetry does - projects and lockfiles
```

Verified: `uv tool install cowsay` then `uv tool run cowsay` worked in about a
second, and `uv python list` shows uv managing its own CPython builds.

`uv` is installed by the `agents` module through winget rather than mise. That
is deliberate: winget puts it on the machine PATH, so it works in cmd, in
Windows PowerShell 5.1, and in any shell that has never activated mise. Tools
the ML stack might reach for should not depend on shell activation. If you
prefer it managed, `mise use -g uv` works too - just do not run both.

### fnm is no longer installed

It was in the `agents` module to give the npm-based agents a node. mise does
that and four other languages, so keeping both meant two managers shimming
`node` with PATH order deciding the winner.

If a previous install of this repo put fnm on your machine, nothing here
removes it - uninstall it yourself if you want it gone, and make sure mise is
earlier on PATH until you do:

```powershell
winget uninstall --id Schniz.fnm -e
```

### Rust, if you want rustup as well

`mise use -g rust@latest` is enough for most work. If you want the canonical
toolchain manager - `rustup toolchain`, nightly, cross targets - install it
alongside and keep only one of the two on PATH:

```powershell
winget install --id Rustlang.Rustup -e
```

Inside WSL, `install-almalinux.sh` already installs rustup; that side is
unchanged.

### mise's own documentation

This repo installs and configures mise; it does not wrap it. For anything
beyond the above, go to the source:

| | |
|---|---|
| [Getting started](https://mise.jdx.dev/getting-started.html) | install, activate, first tool |
| [Dev tools](https://mise.jdx.dev/dev-tools/) | how `use` / `install` / `up` actually behave |
| [Configuration](https://mise.jdx.dev/configuration.html) | `.mise.toml`, `.tool-versions`, config precedence |
| [Registry](https://mise.jdx.dev/registry.html) | every tool mise knows, and which backend serves it |
| [`mise use`](https://mise.jdx.dev/cli/use.html) | the one command you will type most |
| [Environments](https://mise.jdx.dev/environments/) | per-directory env vars, secrets |
| [IDE integration](https://mise.jdx.dev/ide-integration.html) | making VS Code and JetBrains see mise versions |
| [FAQ](https://mise.jdx.dev/faq.html) | including the Windows notes |

Per language: [node](https://mise.jdx.dev/lang/node.html),
[python](https://mise.jdx.dev/lang/python.html),
[go](https://mise.jdx.dev/lang/go.html),
[rust](https://mise.jdx.dev/lang/rust.html). Dart has no page of its own; it is
served from the [registry](https://mise.jdx.dev/registry.html) like the other
community-backed tools.

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
