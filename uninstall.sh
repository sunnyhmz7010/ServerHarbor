#!/usr/bin/env bash

set -euo pipefail

INSTALL_ROOT="/opt/serverharbor"
APP_ROOT="${INSTALL_ROOT}/app"
DATA_ROOT="${INSTALL_ROOT}/data"
BIN_PATH="/usr/local/bin/shr"
MANIFEST_PATH="${INSTALL_ROOT}/.serverharbor-install"
INTERRUPT_REQUESTED=0
CRITICAL_SECTION=0
KEEP_DATA=0

handle_interrupt() {
  if [[ "${CRITICAL_SECTION}" -eq 1 ]]; then
    INTERRUPT_REQUESTED=1
    printf '\nInterrupt received. Waiting for the current critical step to finish.\n' >&2
    return 0
  fi
  printf '\nUninstall cancelled.\n' >&2
  exit 130
}

enter_critical_section() {
  CRITICAL_SECTION=1
}

leave_critical_section() {
  CRITICAL_SECTION=0
  if [[ "${INTERRUPT_REQUESTED}" -eq 1 ]]; then
    printf 'Uninstall cancelled.\n' >&2
    exit 130
  fi
}

confirm() {
  local answer
  local lang="${SERVERHARBOR_LANG:-zh}"
  
  if [[ "${lang}" == "en" ]]; then
    printf 'This will remove:\n'
    printf '  - %s\n' "${BIN_PATH}"
    printf '  - %s\n' "${APP_ROOT}"
    printf '  - %s\n' "${MANIFEST_PATH}"
    printf '\nData directory (config, reports, logs):\n'
    printf '  - %s\n' "${DATA_ROOT}"
    printf '\nOptions:\n'
    printf '  [y] Remove everything including data\n'
    printf '  [k] Keep data directory, only remove program\n'
    printf '  [n] Cancel\n'
    printf 'Choose [y/k/N]: '
  else
    printf '将删除以下内容：\n'
    printf '  - %s\n' "${BIN_PATH}"
    printf '  - %s\n' "${APP_ROOT}"
    printf '  - %s\n' "${MANIFEST_PATH}"
    printf '\n数据目录（配置、报告、日志）：\n'
    printf '  - %s\n' "${DATA_ROOT}"
    printf '\n选项：\n'
    printf '  [y] 删除所有内容（包括数据）\n'
    printf '  [k] 保留数据目录，仅删除程序\n'
    printf '  [n] 取消\n'
    printf '请选择 [y/k/N]: '
  fi
  read -r answer < /dev/tty
  
  case "${answer}" in
    [Yy]|[Yy][Ee][Ss])
      KEEP_DATA=0
      return 0
      ;;
    [Kk])
      KEEP_DATA=1
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ "${EUID}" -ne 0 ]]; then
  printf 'Please run uninstall.sh as root.\n' >&2
  exit 1
fi

trap handle_interrupt INT

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
  enter_critical_section
  if grep -q "${APP_ROOT}/menu.sh" "${BIN_PATH}" 2>/dev/null; then
    rm -f "${BIN_PATH}"
  else
    printf 'Refusing to remove %s because it is not managed by ServerHarbor.\n' "${BIN_PATH}" >&2
    exit 1
  fi
  leave_critical_section
fi

enter_critical_section
if [[ "${KEEP_DATA}" -eq 1 ]]; then
  rm -rf "${APP_ROOT}"
  rm -f "${MANIFEST_PATH}"
  printf 'ServerHarbor program removed. Data preserved at %s\n' "${DATA_ROOT}"
else
  rm -rf "${INSTALL_ROOT}"
  printf 'ServerHarbor removed completely.\n'
fi
leave_critical_section
