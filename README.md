<div align="center">
  <h1>ServerMesh</h1>
  <p>Lightweight Shell toolkit for Linux server bootstrap, peer monitoring, backup coordination, and baseline security management.</p>
  <p>
    <a href="https://github.com/sunnyhmz7010/ServerMesh/releases">Releases</a> |
    <a href="https://github.com/sunnyhmz7010/ServerMesh/issues">Issues</a> |
    <a href="https://github.com/sunnyhmz7010/ServerMesh/security/policy">Security</a>
  </p>
</div>

---

## What It Does

ServerMesh is a menu-driven Bash project designed for multi-server Linux operations. Each node can initialize itself, monitor peer nodes, create and rotate backups, verify file integrity, and publish state to GitHub without depending on a permanent central controller.

## Core Capabilities

- Server bootstrap: install common packages, configure BBR, DNS, swap, timezone, and basic SSH hardening.
- Peer probe: collect local node status and probe remote peers listed in `config/peers.conf`.
- Security guard: review failed logins, scan common web attack traces, show firewall state, and maintain integrity baselines.
- Backup guard: archive watched paths, prune expired backups, and sync the latest archive to peer servers.
- Git sync: initialize the repository, configure the GitHub remote, commit generated state, and push updates.
- Scheduler: install recurring cron tasks for probes, reports, backups, and automatic Git pushes.

## Quick Start

```bash
chmod +x menu.sh
./menu.sh
```

Before running production actions, update:

- `config/app.conf`
- `config/peers.conf`
- `config/watch.conf`

## Typical Workflow

```bash
./menu.sh
# 1 -> full bootstrap on a new server
# 2 -> probe peer servers and generate reports
# 4 -> create backup archives and sync them to peers
# 6 -> bind the GitHub remote and push the latest state
# 7 -> install cron tasks for unattended execution
```

## Project Layout

- `menu.sh`: interactive entry point and cron-oriented CLI modes.
- `lib/`: shared helpers, configuration loading, logging, and report utilities.
- `modules/`: functional modules for bootstrap, probe, security, backup, Git sync, and scheduling.
- `config/`: editable runtime settings for DNS, swap, peers, and watched paths.
- `reports/`, `state/`, `backups/`, `logs/`: generated runtime artifacts.

## GitHub Integration

The default remote for this repository is:

```bash
https://github.com/sunnyhmz7010/ServerMesh
```

Use the Git Sync menu to set `origin`, commit current project state, and push reports or state snapshots to GitHub on a schedule.

## Local Development

Shell syntax check:

```bash
bash -n menu.sh
```

Interactive run:

```bash
./menu.sh
```

## Security

Please use GitHub private vulnerability reporting or contact `mail@sunnyhmz.top` for sensitive security issues.

## License

This project is licensed under the GNU General Public License v3.0. See `LICENSE` for details.
