# Contributing to ServerHarbor

Thank you for your interest in contributing to ServerHarbor! This document provides guidelines and information for contributors.

## Development Environment

### Prerequisites

- Linux environment (Ubuntu/Debian/CentOS)
- Bash 4.0+
- Git

### Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ServerHarbor.git
   cd ServerHarbor
   ```
3. Make your changes
4. Test your changes

## Code Style

### Shell Script Guidelines

- Use `set -euo pipefail` at the beginning of all scripts
- Use 2-space indentation
- Use lowercase for variable names, UPPERCASE for constants
- Quote all variables: `"${variable}"` not `$variable`
- Use `[[ ]]` for conditionals, not `[ ]`
- Add comments for complex logic only
- Keep functions focused and small

### Naming Conventions

- Functions: `ng_` prefix for shared functions (e.g., `ng_log`, `ng_validate_integer`)
- Variables: `NG_` prefix for global constants (e.g., `NG_LANG`, `NG_DATA_ROOT`)
- Files: lowercase with hyphens for multi-word names

## Testing

### Syntax Check

Run syntax check before committing:

```bash
bash -n menu.sh lib/common.sh modules/*.sh install.sh run.sh uninstall.sh
```

### Manual Testing

1. Test the interactive menu:
   ```bash
   ./menu.sh
   ```

2. Test CLI mode:
   ```bash
   ./menu.sh --cron-probe
   ./menu.sh --cron-security
   ```

3. Test install/uninstall:
   ```bash
   sudo ./install.sh
   sudo ./uninstall.sh
   ```

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes
3. Run syntax check
4. Test your changes manually
5. Update documentation if needed
6. Submit a pull request

### PR Description

- Describe what changes you made
- Explain why the changes are needed
- Reference any related issues
- Include testing steps

## Reporting Issues

### Bug Reports

Use the bug report template and include:
- ServerHarbor version
- Linux distribution and version
- Steps to reproduce
- Expected behavior
- Actual behavior
- Error messages or logs

### Feature Requests

Use the feature request template and include:
- Problem description
- Proposed solution
- Alternatives considered

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

For security issues, please refer to our [Security Policy](SECURITY.md).

## License

By contributing to ServerHarbor, you agree that your contributions will be licensed under the GPL-3.0 License.
