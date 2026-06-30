# AGENTS.md

## Repository-Specific Rules

This repository is `ServerHarbor`, a Bash-based Linux multi-server operations toolkit.

### Menu Structure (as of v1.0.0)

Main menu:
- `[1]` System bootstrap — base packages, Docker, network tuning, system status, report, data migration
- `[2]` Security — security report, failed logins, web requests, firewall, integrity baseline/verify, watch paths, security score
- `[3]` Node management — node list, mutual trust setup, remote execution
- `[4]` Update
- `[5]` Uninstall (installed mode only)
- `[0]` Exit

CLI modes: `--cron-probe`, `--cron-security`, `--cron-alerts`

## Project Summary

- Product goal: provide a lightweight Shell toolkit for new-server bootstrap, decentralized peer health checks, and security inspection with integrity verification.
- Main audience: Linux operations learners and administrators who want a practical Shell automation project.
- Runtime target: Linux servers with Bash, common networking tools, and optional systemd.

## Tech Stack

- Language: `Bash`
- Target platform: `Linux`
- VCS host: `GitHub`
- Transport: `ssh`, `curl`, `tar`

## Important Paths

- Interactive entry point: `menu.sh`
- One-command runner: `run.sh`
- Installer and remover: `install.sh`, `uninstall.sh`
- Shared helpers: `common.sh`
- Functional scripts: `bootstrap.sh`, `nodes.sh`, `security.sh`
- Default config: `serverharbor.conf` (root)
- Runtime data root: `${NG_DATA_ROOT}/` (flat, no config/ subdirectory)
- Runtime config: `${NG_DATA_ROOT}/serverharbor.conf`
- Runtime node config: embedded in `serverharbor.conf` (TSV between `__NODES__` markers)
- Generated state: `${NG_DATA_ROOT}/state/`
- Generated reports: `${NG_DATA_ROOT}/reports/`
- Runtime logs: `${NG_DATA_ROOT}/logs/`
- Installed code root: `/opt/serverharbor/app`
- Installed mutable data root: `/opt/serverharbor/data`

## README Rules

- Keep the README concise and user-facing.
- Document the Linux target clearly; do not imply Windows-native execution support beyond editing or Git management.
- Keep examples copyable and based on plain `bash` commands.
- If bootstrap, security, probe, or peer config behavior changes, update the README in the same task.
- README emoji convention: `✨` for motivation, `🚀` for core capabilities, `⚡` for quick start, `📖` for usage, `🧠` for details, `🧱` for tech stack, `🗂️` for project structure, `👨‍💻` for local development, `🔐` for security, `📄` for license, `⭐` for star history. Sub-headers under each section also use emoji prefixes.

## Product Constraints

- This project is a Shell toolkit, not a full orchestration platform.
- Do not introduce centralized service discovery, consensus, or automatic failover without explicit user request.
- Keep the design lightweight and script-first.
- Prefer configuration through a single `serverharbor.conf` file (KEY=VALUE settings + TSV node block).
- Zero external dependencies beyond bash and standard Linux tools (grep, awk, sed, ssh, curl, tar).
- Do not define config variables in `common.sh` or `serverharbor.conf` unless they are actively read by at least one function. Orphaned config variables (defined but never read) must be removed.

## Runtime Model

- `menu.sh` is the interactive user entry point.
- Supported CLI entry points are `menu.sh --cron-probe`, `menu.sh --cron-security`, and `menu.sh --cron-alerts`.
- Bootstrap and hardening functions may require root privileges.
- Peer monitoring is file-driven through the `__NODES__` TSV block in `${NG_DATA_ROOT}/serverharbor.conf`.
- Integrity scanning is path-driven through `NG_WATCH_PATHS` in `${NG_DATA_ROOT}/serverharbor.conf`.
- Managed code and mutable user data must stay decoupled. Installer updates may replace `/opt/serverharbor/app`, but must preserve user config and runtime data under `/opt/serverharbor/data`.
- Before any installer package operation or filesystem write, the script must print the intended actions and require explicit user confirmation.
- Generated reports and state files may be retained locally for inspection, but logs should stay ignored unless requested otherwise.

### Data Isolation Between Online and Installed Modes

- Online mode (`curl | bash`) always uses `~/.config/serverharbor` as its data directory, even if ServerHarbor is installed. This is enforced by checking `SERVERHARBOR_RUNTIME=online` before checking the install manifest.
- Installed mode (`shr`) always uses `/opt/serverharbor/data` as its data directory.
- The two data directories are completely independent. Changes in one mode do not affect the other.
- When running online mode and an install is detected, the user is warned that the data stores are separate.
- The installer (`install.sh`) automatically detects and offers to migrate online data during fresh install.
- The bootstrap menu `[6]` (data migration) is only visible in installed mode. It migrates data from the online directory to the installed directory.
- After migration, the source directory is renamed to `~/.config/serverharbor.migrated` to prevent duplicate migration and signal that the data has been transferred.
- If `.migrated` directory already exists, the migration function reports this and skips.
- Both migration paths detect: `serverharbor.conf`, `state/`, `reports/`, `logs/`.

## Development Commands

- Syntax check:
  - `bash -n menu.sh common.sh bootstrap.sh security.sh nodes.sh install.sh run.sh uninstall.sh`
- One-command online run:
  - `bash <(curl -q -fsSL "https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/run.sh?$(date +%s)")`
- Install globally:
  - `curl -q -fsSL "https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/install.sh?$(date +%s)" | sudo bash`
- Installed shortcut command:
  - `shr`
- Search:
  - `rg "pattern" .`
- Interactive run:
  - `./menu.sh`
- GitHub remote:
  - `https://github.com/sunnyhmz7010/ServerHarbor`

## Codebase Notes

- Keep module boundaries simple: one operational area per file in root directory.
- Shared defaults and helper functions belong in `common.sh`.
- Node management functions belong in `nodes.sh`.
- Prefer a flat directory structure. Avoid second-level subdirectories unless the volume of files genuinely requires grouping. Merge related shell functions into the same file rather than splitting across many small files.
- Every function must have a corresponding menu entry or CLI entry point. If a function is not reachable from any menu option or CLI flag, it is dead code and must be deleted. Do not keep "potential" or "future" functions without a wired entry point.
- Do not add features that are not reflected in the menu UI. If a feature is removed from the menu, its implementation function must also be removed.
- README and menu descriptions must exactly match the actual available features. Never advertise a feature in docs or UI text that does not exist in the code.
- `ng_security_report()` must not duplicate logic from individual scan functions. Keep report generation DRY by reusing existing helpers.
- `install.sh` and `run.sh` are standalone entry-point scripts (not sourced from `menu.sh`). Some code duplication across them is architecturally unavoidable (e.g., `detect_pkg_manager`, `require_cmd`, `acquire_lock`). Do not try to consolidate these into `common.sh`.
- Favor readable shell over dense one-liners when a function has side effects.
- Keep comments sparse and only where the logic is not obvious.
- Use ASCII in scripts unless a file already needs non-ASCII content.

## Shell Portability Lessons

### Piped stdin (`curl | bash`)

- When a script runs via `curl ... | bash`, stdin is the pipe, not the terminal.
- All `read` calls must use `read ... < /dev/tty` to read user input.
- Apply this to: language selection, confirmations, and any interactive prompt.
- If stdin is not a terminal and `/dev/tty` is unavailable, fall back to sensible defaults.

### `set -e` and exit code capture

- `set -e` causes the parent script to exit when a child script returns non-zero.
- To capture a child's exit code, use: `child; code=$?` with `set +e` around it, or `child || code=$?`.
- Do not rely on `if ! child; then code=$?` inside `set -e` — it may still exit.

### `exec` and process substitution

- When a script runs via `bash <(curl ...)`, `$0` is a temporary fd like `/dev/fd/63`.
- `exec bash "$0"` will fail after the fd closes.
- To restart, download the script to a temp file first, then `exec bash "${tmpfile}"`.
- The run.sh refresh mechanism uses this pattern: download to temp file, then `exec bash`.

### Subshell variable scoping with pipes

- Pipes create subshells in Bash. Variables modified inside `while read` loops on the right side of a pipe are lost when the subshell exits.
- Wrong: `cat file | while read -r line; do ((count++)); done` — `count` is always 0 after the loop.
- Right: `while read -r line; do ((count++)); done < file` — input redirection keeps the loop in the current shell.
- This applies to: success/failure counters, accumulated results, and any variable that must survive the loop.

### Echo vs printf for variable output

- Do not use `echo "${variable}" | grep ...` when the variable might contain escape sequences like `-n`, `-e`, or `\t`.
- Prefer `[[ "${variable}" == *"pattern"* ]]` for simple substring checks (no pipe needed).
- If a pipe is required, use `printf '%s\n' "${variable}" | grep ...` instead of `echo`.

### PCRE and grep portability

- Do not use `grep -P` (Perl-compatible regex). It is not available on all Linux distributions (e.g., Alpine, minimal installs).
- Use `grep -E` (extended regex) or `grep -F` (fixed string) instead.
- When parsing CPU or memory from system tools, prefer reading `/proc/stat` or `/proc/meminfo` over `top` or `vmstat`, which have inconsistent output formats across distributions.

## Repository Release Conventions

- Tags should use `vX.Y.Z`.
- Keep release notes focused on user-visible Shell capabilities and operational changes.
- If adding CI/CD later, document workflow behavior here and in README only when relevant to users.

## Version History

### v1.0.0 (2026-06-26)
- Initial release
- System bootstrap (base packages, Docker, network tuning)
- Security audit (login stats, web attacks, firewall, integrity baseline, security score)
- Node management (TSV config, SSH, batch commands, config sync, mutual trust, remote execute)
- Interactive bilingual menu (Chinese/English)
- CLI modes: --cron-probe, --cron-security, --cron-alerts
- Install/uninstall scripts, online run mode
- System alert threshold detection (CPU/Memory/Disk)
- Node selection for batch operations
- Detailed beautified reports with sections and summaries
- Single config file (serverharbor.conf) with TSV node block
- Zero jq dependency (pure bash + grep/awk/sed)
