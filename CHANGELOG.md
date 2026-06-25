# Changelog

All notable changes to ServerHarbor will be documented in this file.

## [Unreleased]

### Added
- System alert threshold detection (CPU/Memory/Disk)
- CLI mode: `--cron-alerts` for system alert checking
- jq auto-installation in nodes.sh

### Fixed
- Unified node configuration (servers.json preferred over peers.conf)

### Removed
- CI workflow (no GitHub Actions needed)
- Dead code cleanup: removed 16 unused functions across all modules
- Removed rootkit detection, port scan, backup management, log viewing, join command (unused features)

## [v1.0.0] - 2026-06-24

### Added
- Initial release
- System bootstrap (base packages, Docker, network tuning scripts)
- Security audit (login stats, web attacks, firewall, integrity baseline, security score)
- Node management (JSON config, SSH connection, batch commands, config sync)
- Interactive menu system
- CLI mode for cron jobs (`--cron-probe`, `--cron-security`)
- Install/uninstall scripts
- Online run mode (curl | bash)
- Bilingual support (Chinese/English)
