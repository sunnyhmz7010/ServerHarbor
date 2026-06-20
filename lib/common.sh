#!/usr/bin/env bash

set -euo pipefail

NG_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NG_MODULE_DIR="${NG_PROJECT_ROOT}/modules"
NG_HOSTNAME="$(hostname 2>/dev/null || echo unknown-host)"
NG_PROJECT_NAME="ServerHarbor"
NG_INSTALL_ROOT="/opt/serverharbor"
NG_INSTALL_DATA="${NG_INSTALL_ROOT}/data"
NG_ONLINE_DATA="${SERVERHARBOR_HOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/serverharbor}"

if [[ -f "${NG_INSTALL_ROOT}/.serverharbor-install" ]]; then
  NG_RUNTIME_MODE="installed"
  NG_DATA_ROOT="${NG_INSTALL_DATA}"
else
  NG_RUNTIME_MODE="online"
  NG_DATA_ROOT="${NG_ONLINE_DATA}"
fi

NG_LANG="${SERVERHARBOR_LANG:-zh}"
NG_CONFIG_DIR="${NG_DATA_ROOT}/config"
NG_LOG_DIR="${NG_DATA_ROOT}/logs"
NG_REPORT_DIR="${NG_DATA_ROOT}/reports"
NG_STATE_DIR="${NG_DATA_ROOT}/state"
NG_TMP_DIR="${NG_DATA_ROOT}/tmp"
NG_CONFIG_FILE="${NG_CONFIG_DIR}/app.conf"
NG_PEERS_FILE="${NG_CONFIG_DIR}/peers.conf"
NG_WATCH_FILE="${NG_CONFIG_DIR}/watch.conf"
NG_INTEGRITY_DB="${NG_STATE_DIR}/integrity.sha256"
NG_DEFAULT_CONFIG_DIR="${NG_PROJECT_ROOT}/config"
NG_COLOR_ENABLED=0
NG_C_RESET=""
NG_C_DIM=""
NG_C_BOLD=""
NG_C_ACCENT=""
NG_C_ACCENT_2=""
NG_C_OK=""
NG_C_WARN=""
NG_C_ERR=""
NG_C_PANEL=""
NG_C_PANEL_2=""

ng_migrate_config() {
  local source_dir=""
  local target_dir="${NG_DATA_ROOT}"

  if [[ "${NG_RUNTIME_MODE}" == "installed" ]] && [[ -d "${NG_ONLINE_DATA}/config" ]]; then
    source_dir="${NG_ONLINE_DATA}"
  fi

  if [[ -z "${source_dir}" ]]; then
    return 0
  fi

  if [[ ! -f "${target_dir}/config/app.conf" ]] && [[ -f "${source_dir}/config/app.conf" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Migrating config from %s to %s\n' "${source_dir}" "${target_dir}"
    else
      printf '正在迁移配置文件从 %s 到 %s\n' "${source_dir}" "${target_dir}"
    fi
    mkdir -p "${target_dir}/config" "${target_dir}/state"
    cp -n "${source_dir}/config/"*.conf "${target_dir}/config/" 2>/dev/null || true
    cp -n "${source_dir}/state/"* "${target_dir}/state/" 2>/dev/null || true
  fi
}

ng_init_environment() {
  mkdir -p "${NG_CONFIG_DIR}" "${NG_LOG_DIR}" "${NG_REPORT_DIR}" "${NG_STATE_DIR}" "${NG_TMP_DIR}"

  ng_migrate_config
  ng_init_theme
  ng_seed_default_configs

  if [[ -f "${NG_CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${NG_CONFIG_FILE}"
  fi

  : "${NG_TIMEZONE:=Asia/Shanghai}"
  : "${NG_DNS_PRIMARY:=1.1.1.1}"
  : "${NG_DNS_SECONDARY:=8.8.8.8}"
  : "${NG_SWAP_SIZE_MB:=1024}"
  : "${NG_PROBE_TIMEOUT:=2}"
  : "${NG_ALERT_CPU_THRESHOLD:=80}"
  : "${NG_ALERT_MEM_THRESHOLD:=80}"
  : "${NG_ALERT_DISK_THRESHOLD:=90}"
}

ng_init_theme() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    NG_COLOR_ENABLED=1
    NG_C_RESET=$'\033[0m'
    NG_C_DIM=$'\033[2m'
    NG_C_BOLD=$'\033[1m'
    NG_C_ACCENT=$'\033[38;5;45m'
    NG_C_ACCENT_2=$'\033[38;5;111m'
    NG_C_OK=$'\033[38;5;78m'
    NG_C_WARN=$'\033[38;5;214m'
    NG_C_ERR=$'\033[38;5;203m'
    NG_C_PANEL=$'\033[38;5;67m'
    NG_C_PANEL_2=$'\033[38;5;240m'
  fi
}

ng_color() {
  local color="$1"
  shift
  if [[ "${NG_COLOR_ENABLED}" -eq 1 ]]; then
    printf '%s%s%s' "${color}" "$*" "${NG_C_RESET}"
  else
    printf '%s' "$*"
  fi
}

ng_repeat() {
  local char="$1"
  local count="$2"
  local output=""

  while (( count > 0 )); do
    output+="${char}"
    count=$((count - 1))
  done

  printf '%s' "${output}"
}

ng_rule() {
  local width="${1:-68}"
  printf '%s\n' "$(ng_color "${NG_C_PANEL_2}" "$(ng_repeat '─' "${width}")")"
}

ng_print_title_box() {
  local title="$1"
  local subtitle="${2:-}"
  local width=68

  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "┌$(ng_repeat '─' "${width}")")"
  printf '%s  %s\n' "$(ng_color "${NG_C_PANEL}" "│")" "$(ng_color "${NG_C_BOLD}${NG_C_ACCENT}" "${title}")"
  if [[ -n "${subtitle}" ]]; then
    printf '%s  %s\n' "$(ng_color "${NG_C_PANEL}" "│")" "$(ng_color "${NG_C_DIM}" "${subtitle}")"
  fi
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "└$(ng_repeat '─' "${width}")")"
}

ng_print_option() {
  local key="$1"
  local icon="$2"
  local label="$3"
  local description="${4:-}"

  printf '  %s %s %s\n' \
    "$(ng_color "${NG_C_ACCENT}" "[${key}]")" \
    "$(ng_color "${NG_C_ACCENT_2}" "${icon}")" \
    "${label}"

  if [[ -n "${description}" ]]; then
    printf '      %s\n' "$(ng_color "${NG_C_DIM}" "${description}")"
  fi
}

ng_print_stat() {
  local label="$1"
  local value="$2"
  local icon="${3:-•}"

  printf '  %s %-10s %s\n' \
    "$(ng_color "${NG_C_ACCENT_2}" "${icon}")" \
    "$(ng_color "${NG_C_DIM}" "${label}")" \
    "${value}"
}

ng_print_header() {
  printf '\n%s %s %s\n' \
    "$(ng_color "${NG_C_DIM}" "[$(date '+%F %T')]")" \
    "$(ng_color "${NG_C_ACCENT_2}" "•")" \
    "$(ng_color "${NG_C_BOLD}" "$1")"
  ng_rule
}

ng_print_menu_hint() {
  printf '%s\n' "$(ng_color "${NG_C_DIM}" "$(ng_t menu_hint)")"
}

ng_report_rule() {
  printf '%s\n' '======================================================================'
}

ng_report_title() {
  local title="$1"
  ng_report_rule
  printf '%s\n' "${title}"
  ng_report_rule
}

ng_report_section() {
  local title="$1"
  printf '\n[%s]\n' "${title}"
  printf '%s\n' '----------------------------------------------------------------------'
}

ng_report_kv() {
  local key="$1"
  local value="$2"
  printf '%-14s %s\n' "${key}" "${value}"
}

ng_report_note() {
  printf '  %s\n' "$1"
}

ng_report_box() {
  local width=68
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╔$(ng_repeat '═' "${width}")")"
}

ng_report_footer() {
  local width=68
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╚$(ng_repeat '═' "${width}")")"
}

ng_report_header() {
  local title="$1"
  local width=68
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╔$(ng_repeat '═' "${width}")")"
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_BOLD}${NG_C_ACCENT}" "${title}")"
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╠$(ng_repeat '═' "${width}")")"
}

ng_report_meta() {
  local key="$1"
  local value="$2"
  printf '%s %-10s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_DIM}" "${key}")" "${value}"
}

ng_report_section_start() {
  local title="$1"
  local width=68
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╠$(ng_repeat '─' "${width}")")"
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_BOLD}" "${title}")"
}

ng_report_line() {
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$1"
}

ng_report_kv_styled() {
  local key="$1"
  local value="$2"
  printf '%s %-14s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_DIM}" "${key}")" "${value}"
}

ng_t() {
  local key="$1"
  case "${NG_LANG}" in
    en)
      case "${key}" in
        press_enter) printf '\nPress Enter to continue...' ;;
        invalid_option) printf 'Invalid option.\n' ;;
        requires_root) printf 'This function requires root privileges.\n' ;;
        missing_cmd) printf 'Missing required command: %s\n' "$2" ;;
        interrupted) printf '\nInterrupted.\n' ;;
        select) printf '%s' "$(ng_color "${NG_C_ACCENT}" 'Select > ')" ;;
        back) printf '0. Back\n' ;;
        generated_at) printf 'Generated at: %s\n' "$2" ;;
        unsupported_pkg) printf 'Unsupported package manager. Skip base package installation.\n' ;;
        menu_hint) printf 'Enter the number directly. Press Ctrl+C to leave the current menu.\n' ;;
      esac
      ;;
    *)
      case "${key}" in
        press_enter) printf '\n按回车继续...' ;;
        invalid_option) printf '无效选项。\n' ;;
        requires_root) printf '此功能需要 root 权限。\n' ;;
        missing_cmd) printf '缺少必要命令：%s\n' "$2" ;;
        interrupted) printf '\n已中断。\n' ;;
        select) printf '%s' "$(ng_color "${NG_C_ACCENT}" '请选择 > ')" ;;
        back) printf '0. 返回\n' ;;
        generated_at) printf '生成时间：%s\n' "$2" ;;
        unsupported_pkg) printf '暂不支持当前包管理器，已跳过基础软件安装。\n' ;;
        menu_hint) printf '直接输入编号即可，按 Ctrl+C 可离开当前菜单。\n' ;;
      esac
      ;;
  esac
}

ng_read_line() {
  local __var_name="$1"
  local __value=""

  if ! IFS= read -r __value < /dev/tty; then
    ng_t interrupted >&2
    return 130
  fi

  printf -v "${__var_name}" '%s' "${__value}"
}

ng_seed_default_configs() {
  local config_name
  for config_name in app.conf peers.conf watch.conf; do
    if [[ ! -f "${NG_CONFIG_DIR}/${config_name}" && -f "${NG_DEFAULT_CONFIG_DIR}/${config_name}" ]]; then
      cp "${NG_DEFAULT_CONFIG_DIR}/${config_name}" "${NG_CONFIG_DIR}/${config_name}"
    fi
  done

  ng_cleanup_legacy_sample_peers
}

ng_cleanup_legacy_sample_peers() {
  [[ -f "${NG_PEERS_FILE}" ]] || return 0

  if grep -qx 'alpha,192.168.1.10' "${NG_PEERS_FILE}" \
    && grep -qx 'beta,192.168.1.11' "${NG_PEERS_FILE}" \
    && [[ "$(grep -Evc '^\s*#|^\s*$' "${NG_PEERS_FILE}")" -eq 2 ]]; then
    cat > "${NG_PEERS_FILE}" <<'EOF'
# alias,host
# hk-01,203.0.113.10
# sg-01,198.51.100.20
EOF
  fi
}

ng_press_enter() {
  ng_t press_enter
  ng_read_line _ || return 130
}

ng_log() {
  local level="$1"
  shift
  local log_file="${NG_LOG_DIR}/serverharbor.log"
  local level_color="${NG_C_ACCENT}"
  local level_icon="•"

  case "${level}" in
    INFO)
      level_color="${NG_C_OK}"
      level_icon="✔"
      ;;
    WARN)
      level_color="${NG_C_WARN}"
      level_icon="▲"
      ;;
    ERROR)
      level_color="${NG_C_ERR}"
      level_icon="✖"
      ;;
  esac

  printf '[%s] [%s] %s\n' "$(date '+%F %T')" "${level}" "$*" | tee -a "${log_file}" >/dev/null
  printf '%s\n' "$(ng_color "${level_color}" "${level_icon} ${level}: $*")"
}

ng_prompt_yes_no() {
  local prompt="$1"
  local answer

  printf '%s %s' "$(ng_color "${NG_C_WARN}" "${prompt}")" "$(ng_color "${NG_C_DIM}" '[y/N]: ')"
  ng_read_line answer || return 130
  [[ "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

ng_require_cmd() {
  local missing=0
  local cmd

  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      ng_t missing_cmd "${cmd}"
      missing=1
    fi
  done

  return "${missing}"
}

ng_require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    ng_t requires_root
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
      apt-get install -y curl wget procps iproute2 net-tools openssh-client
      ;;
    dnf)
      dnf install -y curl wget procps-ng iproute net-tools openssh-clients
      ;;
    yum)
      yum install -y curl wget procps-ng iproute net-tools openssh-clients
      ;;
    *)
      ng_log "WARN" "$(ng_t unsupported_pkg)"
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

ng_read_peers() {
  [[ -f "${NG_PEERS_FILE}" ]] || return 0
  grep -Ev '^\s*#|^\s*$' "${NG_PEERS_FILE}"
}

ng_peer_count() {
  local count
  count="$(ng_read_peers | wc -l | tr -d ' ')" || count=0
  printf '%s' "${count}"
}

ng_total_node_count() {
  local peer_count
  peer_count="$(ng_peer_count)"
  printf '%s\n' "$((peer_count + 1))"
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

ng_progress_bar() {
  local current="$1"
  local total="$2"
  local width="${3:-50}"
  
  if [[ "${total}" -eq 0 ]]; then
    printf '\r[░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░] 0%%'
    return 0
  fi
  
  local percentage=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))
  
  printf '\r['
  printf '%0.s█' $(seq 1 ${filled} 2>/dev/null) || true
  printf '%0.s░' $(seq 1 ${empty} 2>/dev/null) || true
  printf '] %d%%' "${percentage}"
}

ng_spinner() {
  local pid="$1"
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  
  while kill -0 "${pid}" 2>/dev/null; do
    for ((i=0; i<${#spinstr}; i++)); do
      printf '\r%s' "${spinstr:i:1}"
      sleep "${delay}"
    done
  done
  printf '\r'
}

ng_confirm_enhanced() {
  local prompt="$1"
  local default="${2:-n}"
  local answer
  
  if [[ "${default}" == "y" ]]; then
    printf '%s %s' "$(ng_color "${NG_C_WARN}" "${prompt}")" "$(ng_color "${NG_C_DIM}" "[Y/n]: ")"
  else
    printf '%s %s' "$(ng_color "${NG_C_WARN}" "${prompt}")" "$(ng_color "${NG_C_DIM}" "[y/N]: ")"
  fi
  
  ng_read_line answer || return 130
  
  if [[ -z "${answer}" ]]; then
    [[ "${default}" == "y" ]]
  else
    [[ "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]
  fi
}

ng_select_option() {
  local prompt="$1"
  shift
  local options=("$@")
  local choice
  
  printf '%s\n' "$(ng_color "${NG_C_BOLD}" "${prompt}")"
  for i in "${!options[@]}"; do
    printf '  %s %s\n' "$(ng_color "${NG_C_ACCENT}" "[$((i+1))]")" "${options[i]}"
  done
  
  printf '\n%s' "$(ng_color "${NG_C_ACCENT}" "Select > ")"
  ng_read_line choice || return 130
  
  if [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le "${#options[@]}" ]]; then
    printf '%s\n' "${options[$((choice-1))]}"
    return 0
  fi
  
  return 1
}

ng_show_help() {
  local topic="$1"
  
  case "${topic}" in
    monitor)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'System Monitor Help:\n'
        printf '  - Single snapshot: View current resource usage\n'
        printf '  - Real-time monitor: Continuous monitoring with configurable refresh\n'
        printf '  - Monitor report: Generate detailed system report\n'
        printf '  - System alerts: Check for resource threshold violations\n'
      else
        printf '系统监控帮助:\n'
        printf '  - 单次快照: 查看当前资源使用情况\n'
        printf '  - 实时监控: 可配置刷新间隔的持续监控\n'
        printf '  - 监控报告: 生成详细的系统报告\n'
        printf '  - 系统告警: 检查资源阈值违规情况\n'
      fi
      ;;
    network)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Network Tools Help:\n'
        printf '  - Ping test: Test host connectivity\n'
        printf '  - Traceroute: Trace network path to host\n'
        printf '  - DNS lookup: Query DNS records for domain\n'
        printf '  - Port scan: Scan open ports on host\n'
        printf '  - Bandwidth test: Test internet connection speed\n'
      else
        printf '网络工具帮助:\n'
        printf '  - Ping 测试: 测试主机连通性\n'
        printf '  - 路由追踪: 追踪到主机的网络路径\n'
        printf '  - DNS 查询: 查询域名的 DNS 记录\n'
        printf '  - 端口扫描: 扫描主机开放端口\n'
        printf '  - 带宽测试: 测试互联网连接速度\n'
      fi
      ;;
    security)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Security Tools Help:\n'
        printf '  - Security report: Aggregate security analysis\n'
        printf '  - Failed login statistics: Count failed login source IPs\n'
        printf '  - Suspicious web requests: Inspect nginx access logs\n'
        printf '  - Firewall summary: Display firewall state\n'
        printf '  - Integrity baseline: Create file integrity baseline\n'
      else
        printf '安全工具帮助:\n'
        printf '  - 安全报告: 综合安全分析\n'
        printf '  - 失败登录统计: 统计失败登录来源 IP\n'
        printf '  - 可疑 Web 请求: 检查 nginx 访问日志\n'
        printf '  - 防火墙状态: 显示防火墙状态\n'
        printf '  - 完整性基线: 创建文件完整性基线\n'
      fi
      ;;
    *)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'No help available for topic: %s\n' "${topic}"
      else
        printf '没有关于 %s 的帮助信息\n' "${topic}"
      fi
      ;;
  esac
}
