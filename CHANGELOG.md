# Changelog

All notable changes to ServerHarbor will be documented in this file.

## [Unreleased]

### Added
- System alert threshold detection (CPU/Memory/Disk)
- Cron job setup for automated probe and security checks
- CLI mode: `--cron-alerts` for system alert checking
- jq auto-installation in nodes.sh

### Fixed
- CI workflow paths updated to match new file structure
- Bug report template: ServerMesh → ServerHarbor
- AGENTS.md: updated path references
- Unified node configuration (servers.json preferred over peers.conf)

## [v1.0.0] - 2026-06-24

### Added
- Initial release
- System bootstrap (base packages, Docker, network tuning scripts)
- Security audit (login stats, web attacks, firewall, rootkit detection)
- Node management (JSON config, SSH connection, batch commands, config sync)
- Interactive menu system
- CLI mode for cron jobs (`--cron-probe`, `--cron-security`)
- Install/uninstall scripts
- Online run mode (curl | bash)
- Bilingual support (Chinese/English)
- One-click join command for new servers
- NAT detection and support
- Backup management
