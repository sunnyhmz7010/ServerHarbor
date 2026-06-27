#!/usr/bin/env bash

set -euo pipefail

INSTALL_ROOT="/opt/serverharbor"
APP_ROOT="${INSTALL_ROOT}/app"
DATA_ROOT="${INSTALL_ROOT}/data"
BIN_PATH="/usr/local/bin/shr"
MANIFEST_PATH="${INSTALL_ROOT}/.serverharbor-install"
INTERRUPT_REQUESTED=0   # 中断请求标志
CRITICAL_SECTION=0      # 是否处于关键区段中
KEEP_DATA=0             # 是否保留数据目录
SH_LANG="${SERVERHARBOR_LANG:-${NG_LANG:-zh}}"

# 中断信号处理：关键区段中延迟退出，否则立即取消
handle_interrupt() {
  if [[ "${CRITICAL_SECTION}" -eq 1 ]]; then
    INTERRUPT_REQUESTED=1
    if [[ "${SH_LANG}" == "en" ]]; then
      printf '\nInterrupt received. Waiting for the current critical step to finish.\n' >&2
    else
      printf '\n收到中断信号，等待当前关键步骤完成...\n' >&2
    fi
    return 0
  fi
  if [[ "${SH_LANG}" == "en" ]]; then
    printf '\nUninstall cancelled.\n' >&2
  else
    printf '\n卸载已取消。\n' >&2
  fi
  exit 130
}

# 进入关键区段（禁止中断立即退出）
enter_critical_section() {
  CRITICAL_SECTION=1
}

# 离开关键区段（检查是否有待处理的中断请求）
leave_critical_section() {
  CRITICAL_SECTION=0
  if [[ "${INTERRUPT_REQUESTED}" -eq 1 ]]; then
    if [[ "${SH_LANG}" == "en" ]]; then
      printf 'Uninstall cancelled.\n' >&2
    else
      printf '卸载已取消。\n' >&2
    fi
    exit 130
  fi
}

# 卸载确认提示：支持完全删除、保留数据、取消三种选项
confirm() {
  local answer

  if [[ "${SH_LANG}" == "en" ]]; then
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
  IFS= read -r answer < /dev/tty

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

# --- 文件锁机制 ---
LOCK_FILE="/var/lock/serverharbor.lock"

acquire_lock() {
  install -m 600 /dev/null "${LOCK_FILE}" 2>/dev/null || true
  exec {lock_fd}>"${LOCK_FILE}"
  if ! flock -n "${lock_fd}" 2>/dev/null; then
    if [[ "${SH_LANG}" == "en" ]]; then
      printf 'Another install/uninstall process is running. Aborting.\n' >&2
    else
      printf '另一个安装/卸载进程正在运行，已中止。\n' >&2
    fi
    exit 1
  fi
}

# 检查 root 权限
if [[ "${EUID}" -ne 0 ]]; then
  if [[ "${SH_LANG}" == "en" ]]; then
    printf 'Please run uninstall.sh as root.\n' >&2
  else
    printf '请以 root 身份运行 uninstall.sh。\n' >&2
  fi
  exit 1
fi

# 退出时清理锁文件
cleanup() {
  rm -f "${LOCK_FILE}"
}

trap handle_interrupt INT
trap cleanup EXIT
acquire_lock

# 检查安装清单是否存在（防止误删非 ServerHarbor 管理的文件）
if [[ ! -f "${MANIFEST_PATH}" ]]; then
  if [[ "${SH_LANG}" == "en" ]]; then
    printf 'ServerHarbor manifest not found at %s\n' "${MANIFEST_PATH}" >&2
    printf 'Refusing to remove files that may not belong to ServerHarbor.\n' >&2
  else
    printf '未找到 ServerHarbor 安装清单：%s\n' "${MANIFEST_PATH}" >&2
    printf '拒绝删除可能不属于 ServerHarbor 的文件。\n' >&2
  fi
  exit 1
fi

# 确认卸载
if ! confirm; then
  if [[ "${SH_LANG}" == "en" ]]; then
    printf 'Uninstall cancelled.\n'
  else
    printf '卸载已取消。\n'
  fi
  exit 0
fi

# 步骤 1：删除启动器命令（验证归属后才删除）
if [[ -e "${BIN_PATH}" ]]; then
  enter_critical_section
  if grep -q "${APP_ROOT}/menu.sh" "${BIN_PATH}" 2>/dev/null; then
    rm -f "${BIN_PATH}"
  else
    if [[ "${SH_LANG}" == "en" ]]; then
      printf 'Refusing to remove %s because it is not managed by ServerHarbor.\n' "${BIN_PATH}" >&2
    else
      printf '拒绝删除 %s，因为它不属于 ServerHarbor 管理。\n' "${BIN_PATH}" >&2
    fi
    exit 1
  fi
  leave_critical_section
fi

# 步骤 2：删除程序目录（可选保留数据）
enter_critical_section
if [[ "${KEEP_DATA}" -eq 1 ]]; then
  # 仅删除程序，保留数据目录
  if [[ -n "${APP_ROOT}" && -d "${APP_ROOT}" ]]; then
    rm -rf "${APP_ROOT}"
  fi
  rm -f "${MANIFEST_PATH}"
  if [[ "${SH_LANG}" == "en" ]]; then
    printf 'ServerHarbor program removed. Data preserved at %s\n' "${DATA_ROOT}"
  else
    printf 'ServerHarbor 程序已删除，数据保留在 %s\n' "${DATA_ROOT}"
  fi
else
  # 完全删除（包括数据）
  if [[ -n "${INSTALL_ROOT}" && -d "${INSTALL_ROOT}" ]]; then
    rm -rf "${INSTALL_ROOT}"
  fi
  if [[ "${SH_LANG}" == "en" ]]; then
    printf 'ServerHarbor removed completely.\n'
  else
    printf 'ServerHarbor 已完全删除。\n'
  fi
fi
leave_critical_section
