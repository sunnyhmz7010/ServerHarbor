# AGENTS.md

## Reusable Rules

These rules are written as the shared baseline for this project family.

- Keep the `Reusable Rules` block aligned across sibling repositories unless the user explicitly asks for a deliberate deviation.
- Treat reusable-rule updates as bidirectional synchronization: when shared rules change in one repository, apply the same block to sibling repositories in the same task.
- Keep repository-specific product, packaging, signing, route, architecture, and handoff details under `Repository-Specific Rules`, not in this section.

### General Working Style

- Prefer minimal, targeted changes over broad refactors.
- Preserve existing product copy unless the task requires rewriting it.
- Keep user-facing docs concise and practical; avoid adding AI collaboration notes or marketing filler unless explicitly requested.
- Keep public root `README.md` files user-facing and polished: lead with value, use concise feature/usage framing, include externally useful examples, and avoid internal progress notes, AI handoff notes, operational constraints, or release-process guidance.
- Keep README structure user-journey oriented: what it is, why it matters, what it can do, how to start, how to use or integrate it, then contributor-facing local development notes.
- Keep README prose tight. Group capabilities by user-facing surface or scenario, use concrete statements and copyable minimal examples, and avoid repeating the same capability unless new context is added.
- README license text, license badge, root `LICENSE`, and repository metadata must agree; update them together or explicitly call out intentional differences.
- Contributor rules, AI guidance, handoff notes, release conventions, missing-work notes, and local helper commands belong in `AGENTS.md`, not public docs.
- In public docs, write commands with standard upstream tooling rather than local wrappers, aliases, shell functions, or private helper commands.
- For searches, prefer `rg`.
- Use `apply_patch` for manual edits when the environment is stable.
- Do not run destructive git commands unless explicitly requested.
- Keep the public README style aligned with sibling repositories: use emoji-prefixed section headers, `---` dividers after the intro block, centered footer with `Built with ❤️ by Sunny`, and the same badge/link layout. Only the content differs, not the visual structure.
- Issue templates must be bilingual (Chinese/English) following the pattern in start-your-python: field labels use `English / 中文` format, placeholders provide both languages, and the checklist uses bilingual option text.

### Validation And Hygiene

- Keep the working tree clean before handoff: do not leave local build outputs, dependency caches, debugging screenshots, or temporary troubleshooting files committed or untracked.
- When the environment lacks a required toolchain and the user does not need full local verification, skip heavy verification only when necessary and say so explicitly.
- When repository structure, commands, external capabilities, release process, or recurring engineering pitfalls change, update `AGENTS.md` in the same task. Keeping this file current is required, not optional.
- If newly learned guidance appears reusable across repositories, ask whether to scan sibling `AGENTS.md` files, apply the shared rule, and push those updates.
- For GitHub-hosted repositories, maintain the baseline repository-governance files consistently across projects unless the user explicitly asks for divergence. This baseline includes `LICENSE`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue templates, and similar repo-health/community files.
- "Consistently" does not mean every line must be identical. Keep the structure, tone, and policy baseline aligned, but make the necessary project-specific substitutions for repository name, product name, links, platform fields, and repo-specific facts.
- This repository does not use GitHub Actions. Do not add CI/CD workflow files under `.github/workflows/` unless explicitly requested.

### Security And Review

- Review code with a bug-risk mindset first. Prioritize functional regressions, security issues, breaking changes, and missing tests before style or cleanup suggestions.
- Avoid hardcoding secrets, API tokens, passwords, or private host credentials in repository files.
- SSH connections to managed nodes must use `StrictHostKeyChecking=accept-new`, never `StrictHostKeyChecking=no`. Quote all variable expansions in SSH and SCP option strings to prevent word splitting.
- Any function that edits `/etc`, firewall rules, SSH settings, swap, or cron state must either require explicit user choice from the interactive menu or clearly document the side effect.
- Prefer no-side-effect inspections before enforcement changes when checking security posture.
- For peer synchronization, commit only operational state and non-sensitive reports. Do not commit private keys, host inventories with credentials, or confidential logs.
- When passing user-controlled input to `jq`, always use `--arg` parameterization (e.g., `jq --arg name "$name" '.servers[] | select(.name == $name)'`). Never interpolate variables directly into jq filter strings.
- Password input must use `read -rs` (silent mode) to prevent terminal echo.

### Dependency And Upgrade Rules

- Do not merge dependency or toolchain bumps just to clear alerts. First confirm the repository config is compatible and required verification still passes.
- Treat shell portability changes as compatibility work. If a change depends on GNU-only flags or Linux-specific paths, document that scope in the repository-specific rules or README.

### Release Rules

- Rewrite stable release notes from the commits actually included by the published tag.
- Do not publish release notes that mention internal verification-only details unless explicitly requested.
- GitHub release titles should default to the bare tag name such as `v0.1.0`.
- Never commit private signing material, deployment secrets, or generated local credentials.

## Repository-Specific Rules

This repository is `ServerHarbor`, a Bash-based Linux multi-server operations toolkit.

### Menu Structure (as of v1.0.1)

Main menu:
- `[1]` System bootstrap — base packages, Docker, network tuning, system status, report, data migration
- `[2]` Security — security report, failed logins, web requests, firewall, integrity baseline/verify, watch paths, security score
- `[3]` Node management — list, add, remove, test SSH, probe, batch execute, sync config, deploy SSH keys
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
- Runtime config: `config/`
- Generated state: `state/`
- Generated reports: `reports/`
- Runtime logs: `logs/`
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
- Prefer configuration through plain text files under `config/`.
- Do not define config variables in `common.sh` or `app.conf` unless they are actively read by at least one function. Orphaned config variables (defined but never read) must be removed.

## Runtime Model

- `menu.sh` is the interactive user entry point.
- Supported CLI entry points are `menu.sh --cron-probe`, `menu.sh --cron-security`, and `menu.sh --cron-alerts`.
- Bootstrap and hardening functions may require root privileges.
- Peer monitoring is file-driven through `config/servers.json` (preferred) with fallback to `config/peers.conf` (legacy CSV format).
- Integrity scanning is path-driven through `config/watch.conf`.
- Managed code and mutable user data must stay decoupled. Installer updates may replace `/opt/serverharbor/app`, but must preserve user config and runtime data under `/opt/serverharbor/data`.
- Before any installer package operation or filesystem write, the script must print the intended actions and require explicit user confirmation.
- Generated reports and state files may be retained locally for inspection, but logs should stay ignored unless requested otherwise.

### Data Isolation Between Online and Installed Modes

- Online mode (`curl | bash`) always uses `~/.config/serverharbor` as its data directory, even if ServerHarbor is installed. This is enforced by checking `SERVERHARBOR_RUNTIME=online` before checking the install manifest.
- Installed mode (`shr`) always uses `/opt/serverharbor/data` as its data directory.
- The two data directories are completely independent. Changes in one mode do not affect the other.
- When running online mode and an install is detected, the user is warned that the data stores are separate.
- The installer (`install.sh`) automatically detects and offers to migrate online data during fresh install.
- The bootstrap menu `[7]` (data migration) is only visible in installed mode. It migrates data from the online directory to the installed directory.
- After migration, the source directory is renamed to `~/.config/serverharbor.migrated` to prevent duplicate migration and signal that the data has been transferred.
- If `.migrated` directory already exists, the migration function reports this and skips.
- Both migration paths detect: `servers.json`, `app.conf`, `peers.conf`, `watch.conf`, `state/`, `reports/`, `backups/`, `logs/`.

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
- README, CHANGELOG, and menu descriptions must exactly match the actual available features. Never advertise a feature in docs or UI text that does not exist in the code.
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
- Wrong: `jq ... | while read -r node; do ((count++)); done` — `count` is always 0 after the loop.
- Right: `while read -r node; do ((count++)); done < <(jq ...)` — process substitution keeps the loop in the current shell.
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
