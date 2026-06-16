#!/usr/bin/env bash

set -euo pipefail

INSTALL_ROOT="/opt/serverharbor"
APP_ROOT="${INSTALL_ROOT}/app"
DATA_ROOT="${INSTALL_ROOT}/data"
BIN_PATH="/usr/local/bin/shr"
MANIFEST_PATH="${INSTALL_ROOT}/.serverharbor-install"

confirm() {
  local answer
  printf 'This will remove:\n'
  printf '  - %s\n' "${BIN_PATH}"
  printf '  - %s\n' "${APP_ROOT}"
  printf '  - %s\n' "${DATA_ROOT}"
  printf '  - %s\n' "${MANIFEST_PATH}"
  printf 'Continue? [y/N]: '
  read -r answer
  [[ "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

if [[ "${EUID}" -ne 0 ]]; then
  printf 'Please run uninstall.sh as root.\n' >&2
  exit 1
fi

if [[ ! -f "${MANIFEST_PATH}" ]]; then
  printf 'ServerHarbor manifest not found at %s\n' "${MANIFEST_PATH}" >&2
  printf 'Refusing to remove files that may not belong to ServerHarbor.\n' >&2
  exit 1
fi

if ! confirm; then
  printf 'Uninstall cancelled.\n'
  exit 0
fi

if [[ -e "${BIN_PATH}" ]]; then
  if grep -q "${APP_ROOT}/menu.sh" "${BIN_PATH}" 2>/dev/null; then
    rm -f "${BIN_PATH}"
  else
    printf 'Refusing to remove %s because it is not managed by ServerHarbor.\n' "${BIN_PATH}" >&2
    exit 1
  fi
fi

rm -rf "${INSTALL_ROOT}"

printf 'ServerHarbor removed.\n'
