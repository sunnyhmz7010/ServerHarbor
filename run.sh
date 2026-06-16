#!/usr/bin/env bash

set -euo pipefail

PROJECT_NAME="ServerHarbor"
ARCHIVE_URL="https://github.com/sunnyhmz7010/ServerHarbor/archive/refs/heads/main.tar.gz"
TMP_ROOT="${TMPDIR:-/tmp}"
WORK_DIR="$(mktemp -d "${TMP_ROOT%/}/serverharbor-run-XXXXXX")"
ARCHIVE_PATH="${WORK_DIR}/serverharbor-run.tar.gz"
EXTRACT_DIR="${WORK_DIR}/extract"
DATA_ROOT="${SERVERHARBOR_HOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/serverharbor}"
LANGUAGE="${SERVERHARBOR_LANG:-}"

select_language() {
  local choice

  if [[ -n "${LANGUAGE}" ]]; then
    return 0
  fi

  printf 'Choose language / 选择语言:\n'
  printf '  1. 中文\n'
  printf '  2. English\n'
  printf 'Select / 请选择 [1/2, default: 1]: '
  if ! IFS= read -r choice; then
    LANGUAGE="zh"
    printf '\n'
    return 0
  fi

  case "${choice}" in
    2) LANGUAGE="en" ;;
    *) LANGUAGE="zh" ;;
  esac
}

t() {
  local key="$1"
  case "${LANGUAGE}" in
    en)
      case "${key}" in
        missing_cmd) printf 'Missing required command: %s\n' "$2" ;;
        continue) printf 'Continue? [y/N]: ' ;;
        plan_title) printf '%s online run will perform these actions:\n' "${PROJECT_NAME}" ;;
        plan_tmp) printf '  1. Use a temporary directory under %s\n' "${TMP_ROOT%/}" ;;
        plan_download) printf '  2. Download source archive from %s\n' "${ARCHIVE_URL}" ;;
        plan_data) printf '  3. Use persistent data root %s\n' "${DATA_ROOT}" ;;
        plan_cleanup) printf '  4. Remove the temporary directory after exit\n' ;;
        plan_dep_install) printf '  5. Attempt to install curl/tar via %s\n' "$2" ;;
        plan_dep_status) printf '  5. Dependency status: %s\n' "$2" ;;
        dep_ok) printf 'curl and tar already installed' ;;
        dep_missing) printf 'curl or tar missing' ;;
        dep_need_root) printf 'Missing required commands: curl and/or tar\n' ;;
        dep_need_root_hint) printf 'Please install curl and tar or run install.sh with root privileges.\n' ;;
        dep_installing) printf 'curl or tar not found. Attempting to install them via %s...\n' "$2" ;;
        dep_unsupported) printf 'Unable to auto-install curl/tar: unsupported package manager.\n' ;;
        bad_archive) printf 'Downloaded archive does not look like a valid %s source tree.\n' "${PROJECT_NAME}" ;;
        cancelled) printf 'Run cancelled.\n' ;;
        fetching) printf 'Fetching %s from %s\n' "${PROJECT_NAME}" "${ARCHIVE_URL}" ;;
      esac
      ;;
    *)
      case "${key}" in
        missing_cmd) printf '缺少必要命令：%s\n' "$2" ;;
        continue) printf '是否继续？[y/N]: ' ;;
        plan_title) printf '%s 在线运行将执行以下操作：\n' "${PROJECT_NAME}" ;;
        plan_tmp) printf '  1. 使用临时目录根 %s\n' "${TMP_ROOT%/}" ;;
        plan_download) printf '  2. 从 %s 下载源码压缩包\n' "${ARCHIVE_URL}" ;;
        plan_data) printf '  3. 使用持久化数据目录 %s\n' "${DATA_ROOT}" ;;
        plan_cleanup) printf '  4. 退出后删除临时目录\n' ;;
        plan_dep_install) printf '  5. 尝试通过 %s 安装 curl/tar\n' "$2" ;;
        plan_dep_status) printf '  5. 依赖状态：%s\n' "$2" ;;
        dep_ok) printf 'curl 和 tar 已安装' ;;
        dep_missing) printf '缺少 curl 或 tar' ;;
        dep_need_root) printf '缺少必要命令：curl 和/或 tar\n' ;;
        dep_need_root_hint) printf '请先安装 curl 和 tar，或使用具备 root 权限的 install.sh。\n' ;;
        dep_installing) printf '未找到 curl 或 tar，正在尝试通过 %s 安装...\n' "$2" ;;
        dep_unsupported) printf '无法自动安装 curl/tar：不支持的包管理器。\n' ;;
        bad_archive) printf '下载得到的压缩包不是有效的 %s 源码结构。\n' "${PROJECT_NAME}" ;;
        cancelled) printf '已取消运行。\n' ;;
        fetching) printf '正在从 %s 获取 %s\n' "${ARCHIVE_URL}" "${PROJECT_NAME}" ;;
      esac
      ;;
  esac
}

cleanup() {
  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT INT TERM

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      t missing_cmd "${cmd}" >&2
      exit 1
    fi
  done
}

confirm() {
  local answer
  t continue
  if ! IFS= read -r answer; then
    t cancelled
    return 130
  fi
  [[ "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  else
    echo "unknown"
  fi
}

print_run_plan() {
  local pkg_manager dep_note

  pkg_manager="$(detect_pkg_manager)"
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    dep_note="$(t dep_ok)"
  else
    dep_note="$(t dep_missing)"
  fi

  t plan_title
  t plan_tmp
  t plan_download
  t plan_data
  t plan_cleanup
  if [[ "${EUID}" -eq 0 ]] && { ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; }; then
    t plan_dep_install "${pkg_manager}"
  else
    t plan_dep_status "${dep_note}"
  fi
}

ensure_fetch_tools_installed() {
  local manager

  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${EUID}" -ne 0 ]]; then
    t dep_need_root >&2
    t dep_need_root_hint >&2
    exit 1
  fi

  manager="$(detect_pkg_manager)"
  t dep_installing "${manager}"

  case "${manager}" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y curl tar
      ;;
    dnf)
      dnf install -y curl tar
      ;;
    yum)
      yum install -y curl tar
      ;;
    *)
      t dep_unsupported >&2
      exit 1
      ;;
  esac
}

extract_repo() {
  local extracted_root

  mkdir -p "${EXTRACT_DIR}"
  curl -fsSL "${ARCHIVE_URL}" -o "${ARCHIVE_PATH}"
  tar -xzf "${ARCHIVE_PATH}" -C "${EXTRACT_DIR}"
  extracted_root="$(find "${EXTRACT_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "${extracted_root}" || ! -f "${extracted_root}/menu.sh" ]]; then
    t bad_archive >&2
    exit 1
  fi
  printf '%s\n' "${extracted_root}"
}

main() {
  local extracted_root

  select_language
  require_cmd bash
  print_run_plan
  if ! confirm; then
    exit 130
  fi
  ensure_fetch_tools_installed

  t fetching
  extracted_root="$(extract_repo)"
  chmod +x "${extracted_root}/menu.sh"
  SERVERHARBOR_HOME="${DATA_ROOT}" SERVERHARBOR_LANG="${LANGUAGE}" bash "${extracted_root}/menu.sh" "$@"
}

main "$@"
