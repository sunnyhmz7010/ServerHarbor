#!/usr/bin/env bash

set -euo pipefail

NG_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NG_CONFIG_DIR="${NG_PROJECT_ROOT}/config"
NG_LOG_DIR="${NG_PROJECT_ROOT}/logs"
NG_REPORT_DIR="${NG_PROJECT_ROOT}/reports"
NG_STATE_DIR="${NG_PROJECT_ROOT}/state"
NG_BACKUP_DIR="${NG_PROJECT_ROOT}/backups"
NG_TMP_DIR="${NG_PROJECT_ROOT}/tmp"
NG_MODULE_DIR="${NG_PROJECT_ROOT}/modules"
NG_CONFIG_FILE="${NG_CONFIG_DIR}/app.conf"
NG_PEERS_FILE="${NG_CONFIG_DIR}/peers.conf"
NG_WATCH_FILE="${NG_CONFIG_DIR}/watch.conf"
NG_INTEGRITY_DB="${NG_STATE_DIR}/integrity.sha256"
NG_GIT_IGNORE_FILE="${NG_PROJECT_ROOT}/.gitignore"
NG_HOSTNAME="$(hostname 2>/dev/null || echo unknown-host)"
NG_PROJECT_NAME="ServerHarbor"

ng_init_environment() {
  mkdir -p "${NG_CONFIG_DIR}" "${NG_LOG_DIR}" "${NG_REPORT_DIR}" "${NG_STATE_DIR}" "${NG_BACKUP_DIR}" "${NG_TMP_DIR}"

  if [[ -f "${NG_CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${NG_CONFIG_FILE}"
  fi

  : "${NG_TIMEZONE:=Asia/Shanghai}"
  : "${NG_DNS_PRIMARY:=1.1.1.1}"
  : "${NG_DNS_SECONDARY:=8.8.8.8}"
  : "${NG_SWAP_SIZE_MB:=1024}"
  : "${NG_BACKUP_RETENTION_DAYS:=7}"
  : "${NG_GIT_BRANCH:=main}"
  : "${NG_GIT_REMOTE:=origin}"
  : "${NG_STATE_PUSH_PATH:=state}"
  : "${NG_PROBE_TIMEOUT:=2}"
}

ng_print_header() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$1"
  printf '%s\n' '------------------------------------------------------------'
}

ng_press_enter() {
  printf '\nPress Enter to continue...'
  read -r _
}

ng_log() {
  local level="$1"
  shift
  local log_file="${NG_LOG_DIR}/nebula.log"
  printf '[%s] [%s] %s\n' "$(date '+%F %T')" "${level}" "$*" | tee -a "${log_file}"
}

ng_prompt_yes_no() {
  local prompt="$1"
  local answer
  printf '%s [y/N]: ' "${prompt}"
  read -r answer
  [[ "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

ng_require_cmd() {
  local missing=0
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      printf 'Missing required command: %s\n' "${cmd}"
      missing=1
    fi
  done
  return "${missing}"
}

ng_require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    printf 'This function requires root privileges.\n'
    return 1
  fi
}

ng_detect_pkg_manager() {
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

ng_install_base_packages() {
  local manager
  manager="$(ng_detect_pkg_manager)"

  case "${manager}" in
    apt)
      apt-get update
      apt-get install -y curl wget git rsync cron procps iproute2 net-tools openssh-client
      ;;
    dnf)
      dnf install -y curl wget git rsync cronie procps-ng iproute net-tools openssh-clients
      ;;
    yum)
      yum install -y curl wget git rsync cronie procps-ng iproute net-tools openssh-clients
      ;;
    *)
      ng_log "WARN" "Unsupported package manager. Skip base package installation."
      ;;
  esac
}

ng_write_report() {
  local report_name="$1"
  local content="$2"
  local report_file="${NG_REPORT_DIR}/${report_name}-$(date '+%Y%m%d-%H%M%S').txt"
  printf '%s\n' "${content}" > "${report_file}"
  printf '%s\n' "${report_file}"
}

ng_git_current_branch() {
  if git -C "${NG_PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${NG_PROJECT_ROOT}" branch --show-current 2>/dev/null || echo "-"
  else
    echo "-"
  fi
}

ng_git_remote_url() {
  if git -C "${NG_PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${NG_PROJECT_ROOT}" remote get-url "${NG_GIT_REMOTE}" 2>/dev/null || echo "-"
  else
    echo "-"
  fi
}

ng_read_peers() {
  [[ -f "${NG_PEERS_FILE}" ]] || return 0
  grep -Ev '^\s*#|^\s*$' "${NG_PEERS_FILE}"
}

ng_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

ng_run_safe() {
  local description="$1"
  shift
  ng_print_header "${description}"
  "$@"
}

ng_system_load() {
  uptime 2>/dev/null | awk -F'load average: ' '{print $2}' | tr -d '\r' || echo "unknown"
}

ng_memory_summary() {
  free -h 2>/dev/null || true
}

ng_disk_summary() {
  df -hT 2>/dev/null || true
}

ng_service_state() {
  local service_name="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active "${service_name}" 2>/dev/null || echo "inactive"
  else
    echo "unknown"
  fi
}
