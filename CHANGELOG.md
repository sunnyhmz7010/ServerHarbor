# Changelog

All notable changes to ServerHarbor will be documented in this file.

## [Unreleased]

### Added
- Comprehensive robustness improvements (13 items)
- i18n translation function `ng_msg()` for consistent bilingual support
- `ng_save_config_value()` utility for config file management
- `ng_run_step()` helper for error counting in bootstrap
- File locking for install/uninstall to prevent concurrent execution
- Defensive checks before `rm -rf` operations
- Integer validation function `ng_validate_integer()`
- Port number validation (1-65535, start < end)
- Threshold validation (0-100)
- DNS and BBR idempotency checks
- Config file syntax validation before sourcing
- Refresh retry limit (max 3) to prevent infinite recursion
- CPU usage detection using /proc/stat as primary method
- SSH config override detection in sshd_config.d
- iptables support for firewall hardening
- Atomic state file writing with success verification
- Watch path readability check for integrity scanning
- GitHub Actions CI workflow
- CHANGELOG.md
- CONTRIBUTING.md

### Fixed
- Issue templates: replaced old project name "ServerMesh" with "ServerHarbor"
- Port scan: fixed command injection risk by using environment variables
- Lock files: replaced `eval` with native bash fd syntax
- Lock files: added symlink attack protection with `install -m 600`
- Security score: added /var/log/secure support for RHEL/CentOS
- Local health report: added English translation
- Alert function: fixed return value semantics (now returns 0 always)
- Bootstrap error handling: encapsulated with ng_run_step()

### Security
- Fixed command injection vulnerability in port scanning
- Added symlink attack protection for lock files
- Added config file syntax validation

## [v1.0.0] - 2026-06-22

### Added
- Initial release
- Server bootstrap (BBR, DNS, swap, SSH hardening)
- Node health monitoring (ICMP, SSH, latency)
- Security auditing (failed logins, web attacks, firewall, rootkit)
- System monitoring (CPU, memory, disk, alerts)
- Network tools (ping, traceroute, DNS, port scan, bandwidth)
- File integrity verification
- Bilingual support (Chinese/English)
- Interactive menu system
- CLI mode for cron jobs
- Install/uninstall scripts
- Online run mode (curl | bash)
