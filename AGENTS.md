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

### Validation And Hygiene

- Keep the working tree clean before handoff: do not leave local build outputs, dependency caches, debugging screenshots, or temporary troubleshooting files committed or untracked.
- When the environment lacks a required toolchain and the user does not need full local verification, skip heavy verification only when necessary and say so explicitly.
- When repository structure, commands, external capabilities, release process, or recurring engineering pitfalls change, update `AGENTS.md` in the same task. Keeping this file current is required, not optional.
- If newly learned guidance appears reusable across repositories, ask whether to scan sibling `AGENTS.md` files, apply the shared rule, and push those updates.
- For GitHub-hosted repositories, maintain the baseline repository-governance files consistently across projects unless the user explicitly asks for divergence. This baseline includes `LICENSE`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue templates, and similar repo-health/community files.
- "Consistently" does not mean every line must be identical. Keep the structure, tone, and policy baseline aligned, but make the necessary project-specific substitutions for repository name, product name, links, platform fields, and repo-specific facts.

### Security And Review

- Review code with a bug-risk mindset first. Prioritize functional regressions, security issues, breaking changes, and missing tests before style or cleanup suggestions.
- Avoid hardcoding secrets, API tokens, passwords, or private host credentials in repository files.
- Any function that edits `/etc`, firewall rules, SSH settings, swap, or cron state must either require explicit user choice from the interactive menu or clearly document the side effect.
- Prefer no-side-effect inspections before enforcement changes when checking security posture.
- For peer synchronization, commit only operational state and non-sensitive reports. Do not commit private keys, host inventories with credentials, or confidential logs.

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
- Shared helpers: `lib/common.sh`
- Functional modules: `modules/`
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

## Product Constraints

- This project is a Shell toolkit, not a full orchestration platform.
- Do not introduce centralized service discovery, consensus, or automatic failover without explicit user request.
- Keep the design lightweight and script-first.
- Prefer configuration through plain text files under `config/`.

## Runtime Model

- `menu.sh` is the interactive user entry point.
- Supported CLI entry points are `menu.sh --cron-probe` and `menu.sh --cron-security`.
- Bootstrap and hardening functions may require root privileges.
- Peer monitoring is file-driven through `config/peers.conf`.
- Integrity scanning is path-driven through `config/watch.conf`.
- Managed code and mutable user data must stay decoupled. Installer updates may replace `/opt/serverharbor/app`, but must preserve user config and runtime data under `/opt/serverharbor/data`.
- Before any installer package operation or filesystem write, the script must print the intended actions and require explicit user confirmation.
- Generated reports and state files may be retained locally for inspection, but logs should stay ignored unless requested otherwise.

## Development Commands

- Syntax check:
  - `bash -n menu.sh lib/common.sh modules/*.sh install.sh run.sh uninstall.sh`
- One-command online run:
  - `bash <(curl -fsSL https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/run.sh)`
- Install globally:
  - `curl -fsSL https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/install.sh | sudo bash`
- Installed shortcut command:
  - `shr`
- Search:
  - `rg "pattern" .`
- Interactive run:
  - `./menu.sh`
- GitHub remote:
  - `https://github.com/sunnyhmz7010/ServerHarbor`

## Codebase Notes

- Keep module boundaries simple: one operational area per file under `modules/`.
- Shared defaults and helper functions belong in `lib/common.sh`.
- Favor readable shell over dense one-liners when a function has side effects.
- Keep comments sparse and only where the logic is not obvious.
- Use ASCII in scripts unless a file already needs non-ASCII content.

## Repository Release Conventions

- Tags should use `vX.Y.Z`.
- Keep release notes focused on user-visible Shell capabilities and operational changes.
- If adding CI/CD later, document workflow behavior here and in README only when relevant to users.
