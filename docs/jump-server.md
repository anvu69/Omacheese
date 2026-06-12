# Jump Server Workflow

## Recommended rule

Prefer:

```sshconfig
ProxyJump jump-main
ForwardAgent no
```

Avoid defaulting to:

```sshconfig
ForwardAgent yes
```

Agent forwarding is convenient but increases risk if the jump server is compromised during an active session.

## Example

```sshconfig
Host jump-main
  HostName jump.example.com
  User jumpuser
  Port 22
  ForwardAgent no
  IdentitiesOnly no

Host prod-web-01
  HostName 10.10.10.11
  User almalinux
  Port 22
  ProxyJump jump-main
  ForwardAgent no
  IdentitiesOnly no
```

## Why OpenSSH config should be source of truth

- Works with electerm, ssh, scp, rsync, tmux, Ansible later.
- Easy to version-control after removing secrets.
- Easy to migrate to new machines.
- Avoids lock-in to one SSH manager.
