# NebulaGuard xhj001

NebulaGuard xhj001 is a menu-driven Shell project for Linux final assessment. It focuses on server bootstrap, peer probing, security checks, backup rotation, integrity verification, and GitHub-based state synchronization.

## Run

```bash
chmod +x menu.sh
./menu.sh
```

## Default modules

- Server bootstrap: package install, BBR, DNS, swap, timezone, SSH hardening
- Peer probe: decentralized health checks using `peers.conf`
- Security guard: failed login statistics, suspicious web request scan, firewall summary
- Backup guard: archive important paths and sync to peers
- Git sync: initialize repo, configure GitHub remote, commit and push
- Scheduler: install cron jobs for automatic reports and pushes
