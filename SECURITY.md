# Security policy

## Reporting a vulnerability

Use GitHub's private reporting: **Security -> Report a vulnerability** on this
repository. That opens a private advisory only the maintainer can see. Please
do not open a public issue for something exploitable.

There is no SLA here. This is a personal dotfiles project, not a product, so
expect a reply in days rather than hours.

## What is in scope

This repo is a provisioning setup, so the interesting surface is what it runs
and what it can reach:

- **The install one-liner.** `install.ps1` is fetched over HTTPS and executed.
  It downloads a repo archive and runs `scripts/setup.ps1`. A way to make that
  fetch resolve somewhere else is in scope.
- **Anything that runs elevated.** The WSL and debloat modules ask for admin.
- **The SSH agent bridge.** `configs/wsl/ssh-agent-bridge.sh` relays the
  Windows SSH agent pipe into WSL through npiperelay and socat. A flaw there
  exposes your keys to anything running in the distro.
- **The coding agents.** `-Yolo` passes an agent its skip-permissions flag. It
  is opt-in rather than the default precisely because this machine also holds
  your SSH agent and your work trees. A path that enables it without the user
  asking is a vulnerability.

## What is not

- Third-party tools the setup installs. Report those upstream: komorebi, whkd,
  yasb, Alacritty and herdr are separate projects. See
  [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
- The debloat module removing something you wanted. That is a bug, not a
  vulnerability, so open a normal issue.
- `irm ... | iex` being risky in general. It is, the README says so, and it
  offers the download-then-read alternative.

## Supported versions

The tip of `main`. There are no releases and no backports.
