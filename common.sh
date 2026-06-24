#!/usr/bin/env bash

set -euo pipefail

NG_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    # Basic config file validation - only allow KEY=VALUE patterns
    if grep -qPv '^\s*(#|$|[A-Z_]+=)' "${NG_CONFIG_FILE}" 2>/dev/null; then
      ng_log "WARN" "Config file contains unexpected syntax. Using defaults."
    else
      # shellcheck disable=SC1090
      source "${NG_CONFIG_FILE}"
    fi
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

  # Define package lists for each manager
  local -a pkg_names=()
  local -a pkg_descriptions=()
  
  case "${manager}" in
    apt)
      pkg_names=(curl wget procps iproute2 net-tools openssh-client socat sudo iptables)
      if [[ "${NG_LANG}" == "en" ]]; then
        pkg_descriptions=(
          "HTTP client and data transfer tool"
          "Network downloader"
          "Process management utilities (ps, top, free)"
          "Network configuration tools (ip, ss)"
          "Network debugging tools (netstat, ifconfig)"
          "SSH client for remote access"
          "Multipurpose relay for bidirectional data"
          "Execute commands as superuser"
          "Firewall packet filtering"
        )
      else
        pkg_descriptions=(
          "HTTP 客户端与数据传输工具"
          "网络下载工具"
          "进程管理工具（ps、top、free）"
          "网络配置工具（ip、ss）"
          "网络调试工具（netstat、ifconfig）"
          "SSH 客户端，用于远程连接"
          "多功能双向数据中继工具"
          "以超级用户权限执行命令"
          "防火墙包过滤"
        )
      fi
      ;;
    dnf|yum)
      pkg_names=(curl wget procps-ng iproute net-tools openssh-clients socat sudo iptables)
      if [[ "${NG_LANG}" == "en" ]]; then
        pkg_descriptions=(
          "HTTP client and data transfer tool"
          "Network downloader"
          "Process management utilities (ps, top, free)"
          "Network configuration tools (ip, ss)"
          "Network debugging tools (netstat, ifconfig)"
          "SSH client for remote access"
          "Multipurpose relay for bidirectional data"
          "Execute commands as superuser"
          "Firewall packet filtering"
        )
      else
        pkg_descriptions=(
          "HTTP 客户端与数据传输工具"
          "网络下载工具"
          "进程管理工具（ps、top、free）"
          "网络配置工具（ip、ss）"
          "网络调试工具（netstat、ifconfig）"
          "SSH 客户端，用于远程连接"
          "多功能双向数据中继工具"
          "以超级用户权限执行命令"
          "防火墙包过滤"
        )
      fi
      ;;
    *)
      ng_log "WARN" "$(ng_t unsupported_pkg)"
      return 1
      ;;
  esac

  local pkg_count=${#pkg_names[@]}
  local -a selected=()
  local -a pkg_icons=("🌐" "📥" "⚙️" "🔧" "🔌" "🔑" "🔄" "👑" "🛡")
  for ((i=0; i<pkg_count; i++)); do
    selected+=(1)  # Default: all selected
  done

  # Interactive selection loop
  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "📦 Package Installation" "Select packages to install"
    else
      ng_print_title_box "📦 软件包安装" "选择要安装的软件包"
    fi

    for ((i=0; i<pkg_count; i++)); do
      local status_icon
      if [[ "${selected[i]}" -eq 1 ]]; then
        status_icon="✓"
      else
        status_icon=" "
      fi
      printf '  [%s] %s %-3s %s\n' "${status_icon}" "$(ng_color "${NG_C_ACCENT_2}" "${pkg_icons[i]}")" "$((i+1))" "${pkg_names[i]}"
      printf '          %s\n' "$(ng_color "${NG_C_DIM}" "${pkg_descriptions[i]}")"
    done

    printf '\n'
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '  Enter number to toggle, or:\n'
      printf '  [a] Select all  [n] Deselect all  [y] Confirm  [0] Cancel\n'
    else
      printf '  输入编号切换选择状态，或：\n'
      printf '  [a] 全选  [n] 全不选  [y] 确认安装  [0] 取消\n'
    fi
    printf '\n'

    local choice
    ng_read_line choice || return 130

    case "${choice}" in
      0)
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Installation cancelled.\n'
        else
          printf '已取消安装。\n'
        fi
        return 0
        ;;
      [1-9])
        local idx=$((choice - 1))
        if [[ "${idx}" -ge 0 && "${idx}" -lt "${pkg_count}" ]]; then
          if [[ "${selected[idx]}" -eq 1 ]]; then
            selected[idx]=0
          else
            selected[idx]=1
          fi
        fi
        ;;
      a|A)
        for ((i=0; i<pkg_count; i++)); do
          selected[i]=1
        done
        ;;
      n|N)
        for ((i=0; i<pkg_count; i++)); do
          selected[i]=0
        done
        ;;
      y|Y)
        # Build package list from selected items
        local packages_to_install=()
        for ((i=0; i<pkg_count; i++)); do
          if [[ "${selected[i]}" -eq 1 ]]; then
            packages_to_install+=("${pkg_names[i]}")
          fi
        done

        if [[ ${#packages_to_install[@]} -eq 0 ]]; then
          if [[ "${NG_LANG}" == "en" ]]; then
            printf 'No packages selected.\n'
          else
            printf '未选择任何软件包。\n'
          fi
          return 0
        fi

        if [[ "${NG_LANG}" == "en" ]]; then
          printf '\nInstalling: %s\n\n' "${packages_to_install[*]}"
        else
          printf '\n正在安装：%s\n\n' "${packages_to_install[*]}"
        fi

        case "${manager}" in
          apt)
            apt-get update
            local apt_output
            apt_output=$(apt-get install -y "${packages_to_install[@]}" 2>&1) || true
            printf '%s\n' "${apt_output}"
            
            # Check if apt suggests autoremove
            if echo "${apt_output}" | grep -q "no longer required"; then
              local autoremove_packages
              autoremove_packages=$(apt-get --dry-run autoremove 2>/dev/null | grep "^Remv" | awk '{print $2}' || true)
              
              if [[ -n "${autoremove_packages}" ]]; then
                printf '\n'
                if [[ "${NG_LANG}" == "en" ]]; then
                  printf 'Apt detected packages that can be auto-removed:\n'
                  echo "${autoremove_packages}" | while IFS= read -r pkg; do
                    printf '  - %s\n' "${pkg}"
                  done
                  printf '\n'
                  if ng_prompt_yes_no "Run apt autoremove to clean up?"; then
                    apt-get autoremove -y
                  fi
                else
                  printf '检测到可自动删除的软件包：\n'
                  echo "${autoremove_packages}" | while IFS= read -r pkg; do
                    printf '  - %s\n' "${pkg}"
                  done
                  printf '\n'
                  if ng_prompt_yes_no "是否执行 apt autoremove 清理？"; then
                    apt-get autoremove -y
                  fi
                fi
              fi
            fi
            ;;
          dnf|yum)
            "${manager}" install -y "${packages_to_install[@]}"
            ;;
        esac
        return 0
        ;;
      *)
        ng_t invalid_option
        ;;
    esac
  done
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

ng_validate_integer() {
  local value="$1"
  local min="${2:-0}"
  local max="${3:-999999}"
  [[ "${value}" =~ ^[0-9]+$ ]] && (( value >= min && value <= max ))
}

# System resource monitoring and alerting
ng_get_cpu_usage() {
  top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0"
}

ng_get_memory_usage() {
  free 2>/dev/null | awk '/Mem:/ {printf "%.1f", $3/$2*100}' || echo "0"
}

ng_get_disk_usage() {
  df / 2>/dev/null | awk 'NR==2 {print $5}' | cut -d'%' -f1 || echo "0"
}

ng_check_alerts() {
  local cpu_usage mem_usage disk_usage
  local alerts=()
  
  cpu_usage=$(ng_get_cpu_usage | cut -d'.' -f1)
  mem_usage=$(ng_get_memory_usage | cut -d'.' -f1)
  disk_usage=$(ng_get_disk_usage)
  
  # Check CPU
  if [[ "${cpu_usage}" -gt "${NG_ALERT_CPU_THRESHOLD}" ]]; then
    alerts+=("CPU: ${cpu_usage}% > ${NG_ALERT_CPU_THRESHOLD}%")
  fi
  
  # Check Memory
  if [[ "${mem_usage}" -gt "${NG_ALERT_MEM_THRESHOLD}" ]]; then
    alerts+=("Memory: ${mem_usage}% > ${NG_ALERT_MEM_THRESHOLD}%")
  fi
  
  # Check Disk
  if [[ "${disk_usage}" -gt "${NG_ALERT_DISK_THRESHOLD}" ]]; then
    alerts+=("Disk: ${disk_usage}% > ${NG_ALERT_DISK_THRESHOLD}%")
  fi
  
  # Output alerts
  if [[ "${#alerts[@]}" -gt 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '⚠️  System Alerts:\n'
    else
      printf '⚠️  系统告警:\n'
    fi
    for alert in "${alerts[@]}"; do
      printf '  - %s\n' "${alert}"
    done
    return 1
  fi
  
  return 0
}

ng_show_system_status() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "System Status"
    printf 'CPU Usage:      %s%%\n' "$(ng_get_cpu_usage)"
    printf 'Memory Usage:   %s%%\n' "$(ng_get_memory_usage)"
    printf 'Disk Usage:     %s%%\n' "$(ng_get_disk_usage)"
    printf '\nAlert Thresholds:\n'
    printf '  CPU:    %s%%\n' "${NG_ALERT_CPU_THRESHOLD}"
    printf '  Memory: %s%%\n' "${NG_ALERT_MEM_THRESHOLD}"
    printf '  Disk:   %s%%\n' "${NG_ALERT_DISK_THRESHOLD}"
  else
    ng_print_header "系统状态"
    printf 'CPU 使用率:    %s%%\n' "$(ng_get_cpu_usage)"
    printf '内存使用率:    %s%%\n' "$(ng_get_memory_usage)"
    printf '磁盘使用率:    %s%%\n' "$(ng_get_disk_usage)"
    printf '\n告警阈值:\n'
    printf '  CPU:    %s%%\n' "${NG_ALERT_CPU_THRESHOLD}"
    printf '  内存:   %s%%\n' "${NG_ALERT_MEM_THRESHOLD}"
    printf '  磁盘:   %s%%\n' "${NG_ALERT_DISK_THRESHOLD}"
  fi
  
  printf '\n'
  ng_check_alerts
}


