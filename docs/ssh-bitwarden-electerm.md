# SSH Client Manager: electerm + Bitwarden SSH Agent

## Goal

Use Bitwarden as the SSH key vault/agent and electerm as the GUI SSH/SFTP manager.

## Recommended flow

```text
Bitwarden Desktop SSH Agent
  -> OpenSSH-compatible SSH client
  -> electerm session manager / SFTP / tunnel
```

## Bitwarden

1. Install Bitwarden Desktop.
2. Enable SSH Agent in settings.
3. Import or generate SSH keys as SSH key items.
4. Keep private keys inside Bitwarden vault where possible.

## electerm

Use electerm for:

- SSH session management
- SFTP file transfer
- SSH tunnels
- Jump/bastion access when useful
- Occasional GUI admin tasks

Use Alacritty + tmux + ssh for deeper daily terminal work.

## Notes

- Prefer OpenSSH-compatible clients.
- Avoid PuTTY-style flows if Bitwarden SSH Agent support is required.
- Keep host definitions in OpenSSH config to avoid lock-in.
