#!/usr/bin/env bash

set -euo pipefail

NG_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NG_HOSTNAME="$(hostname 2>/dev/null || echo unknown-host)"
NG_PROJECT_NAME="ServerHarbor"
NG_INSTALL_ROOT="/opt/serverharbor"
NG_INSTALL_DATA="${NG_INSTALL_ROOT}/data"
NG_ONLINE_DATA="${SERVERHARBOR_HOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/serverharbor}"

if [[ "${SERVERHARBOR_RUNTIME:-}" == "online" ]]; then
  NG_RUNTIME_MODE="online"
  NG_DATA_ROOT="${NG_ONLINE_DATA}"
elif [[ -f "${NG_INSTALL_ROOT}/.serverharbor-install" ]]; then
  NG_RUNTIME_MODE="installed"
  NG_DATA_ROOT="${NG_INSTALL_DATA}"
else
  NG_RUNTIME_MODE="online"
  NG_DATA_ROOT="${NG_ONLINE_DATA}"
fi

NG_LANG="${SERVERHARBOR_LANG:-zh}"
NG_LOG_DIR="${NG_DATA_ROOT}/logs"
NG_REPORT_DIR="${NG_DATA_ROOT}/reports"
NG_STATE_DIR="${NG_DATA_ROOT}/state"
NG_CONFIG_FILE="${NG_DATA_ROOT}/serverharbor.conf"
NG_NODES_FILE="${NG_DATA_ROOT}/servers.json"
NG_DEFAULT_CONFIG_DIR="${NG_PROJECT_ROOT}"
NG_WATCH_PATHS="/etc /var/www /root"
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

ng_has_meaningful_data() {
  local dir="$1"
  [[ -f "${dir}/servers.json" ]] && return 0
  [[ -f "${dir}/serverharbor.conf" ]] && return 0
  [[ -d "${dir}/state" ]] && [[ -n "$(ls -A "${dir}/state" 2>/dev/null)" ]] && return 0
  [[ -d "${dir}/reports" ]] && [[ -n "$(ls -A "${dir}/reports" 2>/dev/null)" ]] && return 0
  [[ -d "${dir}/logs" ]] && [[ -n "$(ls -A "${dir}/logs" 2>/dev/null)" ]] && return 0
  return 1
}

ng_do_migration() {
  local source_dir="$1"
  local target_dir="$2"
  local migrated_dir="$3"

  mkdir -p "${target_dir}/state" "${target_dir}/logs" "${target_dir}/reports"

  local copied=0

  for conf_name in servers.json serverharbor.conf; do
    if [[ -f "${source_dir}/${conf_name}" ]]; then
      if [[ -f "${target_dir}/${conf_name}" ]]; then
        if [[ "${NG_LANG}" == "en" ]]; then
          printf '  %s already exists, skipping %s\n' "$(ng_color "${NG_C_WARN}" "⚠")" "${conf_name}"
        else
          printf '  %s 已存在，跳过 %s\n' "$(ng_color "${NG_C_WARN}" "⚠")" "${conf_name}"
        fi
      else
        cp -f "${source_dir}/${conf_name}" "${target_dir}/${conf_name}" 2>/dev/null || true
        printf '  %s %s\n' "$(ng_color "${NG_C_OK}" "✓")" "${conf_name}"
        ((copied++)) || true
      fi
    fi
  done

  for sub_dir in state reports logs; do
    if [[ -d "${source_dir}/${sub_dir}" ]] && [[ -n "$(ls -A "${source_dir}/${sub_dir}" 2>/dev/null)" ]]; then
      local count
      count=$(ls -1 "${source_dir}/${sub_dir}" 2>/dev/null | wc -l)
      cp -rf "${source_dir}/${sub_dir}/"* "${target_dir}/${sub_dir}/" 2>/dev/null || true
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '  %s %s (%d files)\n' "$(ng_color "${NG_C_OK}" "✓")" "${sub_dir}" "${count}"
      else
        printf '  %s %s（%d 个文件）\n' "$(ng_color "${NG_C_OK}" "✓")" "${sub_dir}" "${count}"
      fi
      ((copied++)) || true
    fi
  done

  if [[ "${copied}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Nothing was copied.\n'
    else
      printf '没有复制任何内容。\n'
    fi
    return 0
  fi

  mv "${source_dir}" "${migrated_dir}" 2>/dev/null || true

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\n%s\n' "$(ng_color "${NG_C_OK}" "✓ Migration completed!")"
    printf '  Source renamed to: %s\n' "${migrated_dir}"
  else
    printf '\n%s\n' "$(ng_color "${NG_C_OK}" "✓ 数据迁移完成！")"
    printf '  源目录已重命名为: %s\n' "${migrated_dir}"
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_log "INFO" "Data migrated from ${source_dir} to ${target_dir}, source renamed to ${migrated_dir}"
  else
    ng_log "INFO" "数据已从 ${source_dir} 迁移至 ${target_dir}，源目录重命名为 ${migrated_dir}"
  fi
}

ng_trigger_migration() {
  if [[ "${NG_RUNTIME_MODE}" != "installed" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "Data migration is only available in installed mode."
      printf '  Run the installed version (shr) to use this feature.\n'
    else
      ng_log "WARN" "数据迁移仅在安装模式下可用。"
      printf '  请运行安装版（shr）使用此功能。\n'
    fi
    return 1
  fi

  local online_dir="${NG_ONLINE_DATA}"
  local installed_dir="${NG_DATA_ROOT}"
  local online_migrated="${online_dir}.migrated"
  local installed_migrated="${installed_dir}.migrated"

  local online_has_data=0
  local installed_has_data=0

  if [[ -d "${online_dir}" ]] && ng_has_meaningful_data "${online_dir}"; then
    online_has_data=1
  fi
  if [[ -d "${installed_dir}" ]] && ng_has_meaningful_data "${installed_dir}"; then
    installed_has_data=1
  fi

  if [[ "${online_has_data}" -eq 0 ]] && [[ "${installed_has_data}" -eq 0 ]]; then
    if [[ -d "${online_migrated}" ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '%s\n' "$(ng_color "${NG_C_OK}" "✓ Online data was already migrated to ${online_migrated}")"
      else
        printf '%s\n' "$(ng_color "${NG_C_OK}" "✓ 在线版数据已迁移至 ${online_migrated}")"
      fi
      return 0
    fi
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "No data found to migrate in either location."
    else
      ng_log "WARN" "两个位置都没有可迁移的数据。"
    fi
    return 1
  fi

  if [[ "${online_has_data}" -eq 1 ]] && [[ "${installed_has_data}" -eq 0 ]]; then
    if [[ -d "${online_migrated}" ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '%s\n' "$(ng_color "${NG_C_OK}" "✓ Online data was already migrated to ${online_migrated}")"
      else
        printf '%s\n' "$(ng_color "${NG_C_OK}" "✓ 在线版数据已迁移至 ${online_migrated}")"
      fi
      return 0
    fi
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\n  Online data:   %s\n' "${online_dir}"
      printf '  Installed data: %s (empty)\n\n' "${installed_dir}"
      ng_prompt_yes_no "Migrate online data → installed?" || return 0
    else
      printf '\n  在线版数据:   %s\n' "${online_dir}"
      printf '  安装版数据:   %s（空）\n\n' "${installed_dir}"
      ng_prompt_yes_no "是否迁移在线版数据 → 安装版？" || return 0
    fi
    ng_do_migration "${online_dir}" "${installed_dir}" "${online_migrated}"
    return 0
  fi

  if [[ "${online_has_data}" -eq 0 ]] && [[ "${installed_has_data}" -eq 1 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\n  Installed data: %s\n' "${installed_dir}"
      printf '  Online data:   %s (empty or migrated)\n\n' "${online_dir}"
      printf '  No online data to migrate.\n'
      printf '  Use the online version first to create data, then migrate here.\n'
    else
      printf '\n  安装版数据:   %s\n' "${installed_dir}"
      printf '  在线版数据:   %s（空或已迁移）\n\n' "${online_dir}"
      printf '  没有在线版数据可迁移。\n'
      printf '  请先使用在线版产生数据，再执行迁移。\n'
    fi
    return 0
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\n  Both locations have data:\n'
    printf '    Online data:    %s\n' "${online_dir}"
    printf '    Installed data: %s\n\n' "${installed_dir}"
    printf '  Choose migration direction:\n'
    printf '    [1] Online → Installed (merge online into installed)\n'
    printf '    [2] Installed → Online (merge installed into online)\n'
    printf '    [0] Cancel\n'
  else
    printf '\n  两处都有数据：\n'
    printf '    在线版数据:   %s\n' "${online_dir}"
    printf '    安装版数据:   %s\n\n' "${installed_dir}"
    printf '  选择迁移方向：\n'
    printf '    [1] 在线版 → 安装版（合并到安装版）\n'
    printf '    [2] 安装版 → 在线版（合并到在线版）\n'
    printf '    [0] 取消\n'
  fi

  local dir_choice
  ng_read_line dir_choice || return 130

  case "${dir_choice}" in
    1)
      if [[ -d "${online_migrated}" ]]; then
        if [[ "${NG_LANG}" == "en" ]]; then
          printf '%s\n' "$(ng_color "${NG_C_OK}" "✓ Online data was already migrated to ${online_migrated}")"
        else
          printf '%s\n' "$(ng_color "${NG_C_OK}" "✓ 在线版数据已迁移至 ${online_migrated}")"
        fi
        return 0
      fi
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '\n  Migrating: %s → %s\n\n' "${online_dir}" "${installed_dir}"
      else
        printf '\n  迁移方向: %s → %s\n\n' "${online_dir}" "${installed_dir}"
      fi
      ng_do_migration "${online_dir}" "${installed_dir}" "${online_migrated}"
      ;;
    2)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '\n  Migrating: %s → %s\n\n' "${installed_dir}" "${online_dir}"
      else
        printf '\n  迁移方向: %s → %s\n\n' "${installed_dir}" "${online_dir}"
      fi
      ng_do_migration "${installed_dir}" "${online_dir}" "${installed_migrated}"
      ;;
    0)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Cancelled.\n'
      else
        printf '已取消。\n'
      fi
      ;;
    *)
      ng_t invalid_option
      ;;
  esac
}

ng_init_environment() {
  mkdir -p "${NG_DATA_ROOT}" "${NG_LOG_DIR}" "${NG_REPORT_DIR}" "${NG_STATE_DIR}"

  ng_init_theme
  ng_seed_default_configs

  if [[ "${NG_RUNTIME_MODE}" == "online" ]] && [[ -f "${NG_INSTALL_ROOT}/.serverharbor-install" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\n%s\n' "$(ng_color "${NG_C_WARN}" "⚠ ServerHarbor is installed but running in online mode.")"
      printf '  Installed data: %s\n' "${NG_INSTALL_DATA}"
      printf '  Online data:    %s\n' "${NG_ONLINE_DATA}"
      printf '  These are separate data stores. Use [1]→[7] in installed mode to merge.\n'
    else
      printf '\n%s\n' "$(ng_color "${NG_C_WARN}" "⚠ ServerHarbor 已安装，但当前运行在在线模式。")"
      printf '  安装版数据: %s\n' "${NG_INSTALL_DATA}"
      printf '  在线版数据: %s\n' "${NG_ONLINE_DATA}"
      printf '  两处数据独立，互不影响。如需合并请使用安装版菜单 [1]→[7]。\n'
    fi
  fi

  if [[ -f "${NG_CONFIG_FILE}" ]]; then
    local _line _key _val
    while IFS= read -r _line; do
      [[ "${_line}" =~ ^[[:space:]]*NG_[A-Z_]+= ]] || continue
      _key="${_line%%=*}"
      _key="${_key#"${_key%%[![:space:]]*}"}"
      _val="${_line#*=}"
      _val="${_val#\"}"
      _val="${_val%\"}"
      _val="${_val#\'}"
      _val="${_val%\'}"
      if [[ "${_val}" =~ ^[a-zA-Z0-9_/.:~\ @,+-]*$ ]]; then
        printf -v "${_key}" '%s' "${_val}"
      fi
    done < "${NG_CONFIG_FILE}"
  fi

  : "${NG_PROBE_TIMEOUT:=2}"
  : "${NG_ALERT_CPU_THRESHOLD:=80}"
  : "${NG_ALERT_MEM_THRESHOLD:=80}"
  : "${NG_ALERT_DISK_THRESHOLD:=90}"
  : "${NG_WATCH_PATHS:=/etc /var/www /root}"
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

ng_print_menu_hint() {
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

  printf '  %s %s  %s\n' \
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

ng_print_menu_hint() {
  printf '%s\n' "$(ng_color "${NG_C_DIM}" "$(ng_t menu_hint)")"
}

ng_report_footer() {
  local width=68
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╚$(ng_repeat '═' "${width}")")"
}

ng_service_state() {
  local service_name="$1"
  if command -v systemctl >/dev/null 2>&1; then
    local state
    state=$(systemctl is-active "${service_name}" 2>/dev/null || true)
    if [[ "${state}" == "active" ]]; then
      echo "active"
    elif [[ "${state}" == "inactive" || "${state}" == "failed" ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then echo "inactive"; else echo "未运行"; fi
    else
      if [[ "${NG_LANG}" == "en" ]]; then echo "unknown"; else echo "未知"; fi
    fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then echo "unknown"; else echo "未知"; fi
  fi
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
        success) printf 'Success.\n' ;;
        failed) printf 'Failed.\n' ;;
        cancelled) printf 'Cancelled.\n' ;;
        done) printf 'Done.\n' ;;
        no_nodes) printf 'No nodes configured.\n' ;;
        node_added) printf 'Node added: %s\n' "$2" ;;
        node_removed) printf 'Node removed: %s\n' "$2" ;;
        node_exists) printf 'Node already exists: %s\n' "$2" ;;
        node_not_found) printf 'Node not found: %s\n' "$2" ;;
        testing) printf 'Testing...\n' ;;
        installing) printf 'Installing %s...\n' "$2" ;;
        config_saved) printf 'Configuration saved.\n' ;;
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
        success) printf '操作成功。\n' ;;
        failed) printf '操作失败。\n' ;;
        cancelled) printf '已取消。\n' ;;
        done) printf '完成。\n' ;;
        no_nodes) printf '未配置节点。\n' ;;
        node_added) printf '节点已添加：%s\n' "$2" ;;
        node_removed) printf '节点已删除：%s\n' "$2" ;;
        node_exists) printf '节点已存在：%s\n' "$2" ;;
        node_not_found) printf '节点未找到：%s\n' "$2" ;;
        testing) printf '测试中...\n' ;;
        installing) printf '正在安装 %s...\n' "$2" ;;
        config_saved) printf '配置已保存。\n' ;;
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
  if [[ ! -f "${NG_DATA_ROOT}/serverharbor.conf" && -f "${NG_DEFAULT_CONFIG_DIR}/serverharbor.conf" ]]; then
    cp "${NG_DEFAULT_CONFIG_DIR}/serverharbor.conf" "${NG_DATA_ROOT}/serverharbor.conf"
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
  
  # Default selection: 1,2,7,8,9 (curl, wget, socat, sudo, iptables)
  for ((i=0; i<pkg_count; i++)); do
    case $((i+1)) in
      1|2|7|8|9) selected+=(1) ;;
      *) selected+=(0) ;;
    esac
  done
  
  local do_update=1  # Default: run apt update/upgrade

  # Interactive selection loop
  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "📦 Package Installation" "Select packages to install"
    else
      ng_print_title_box "📦 软件包安装" "选择要安装的软件包"
    fi

    printf '\n'
    
    # Show update option
    local update_icon update_color
    if [[ "${do_update}" -eq 1 ]]; then
      update_icon="✓"
      update_color="${NG_C_OK}"
    else
      update_icon="✗"
      update_color="${NG_C_DIM}"
    fi
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '  %s %s  %s\n' \
        "$(ng_color "${update_color}" "[${update_icon}]")" \
        "$(ng_color "${NG_C_ACCENT}" "[u]")" \
        "${manager} update && ${manager} upgrade (recommended)"
    else
      printf '  %s %s  %s\n' \
        "$(ng_color "${update_color}" "[${update_icon}]")" \
        "$(ng_color "${NG_C_ACCENT}" "[u]")" \
        "${manager} update && ${manager} upgrade（推荐）"
    fi
    printf '\n'
    
    # Show packages
    for ((i=0; i<pkg_count; i++)); do
      local status_icon status_color
      if [[ "${selected[i]}" -eq 1 ]]; then
        status_icon="✓"
        status_color="${NG_C_OK}"
      else
        status_icon="✗"
        status_color="${NG_C_DIM}"
      fi
      printf '  %s %-3s %s %s\n' \
        "$(ng_color "${status_color}" "[${status_icon}]")" \
        "$(ng_color "${NG_C_ACCENT}" "$((i+1))")" \
        "$(ng_color "${NG_C_ACCENT_2}" "${pkg_icons[i]}")" \
        "${pkg_names[i]}"
      printf '        %s\n' "$(ng_color "${NG_C_DIM}" "${pkg_descriptions[i]}")"
    done

    printf '\n'
    printf '%s\n' "$(ng_color "${NG_C_PANEL_2}" "$(ng_repeat '─' 68)")"
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '  %s Toggle  %s Select all  %s Deselect all\n' \
        "$(ng_color "${NG_C_DIM}" "1-9")" \
        "$(ng_color "${NG_C_DIM}" "a")" \
        "$(ng_color "${NG_C_DIM}" "n")"
      printf '  %s Confirm  %s Cancel\n' \
        "$(ng_color "${NG_C_ACCENT}" "y")" \
        "$(ng_color "${NG_C_ACCENT}" "0")"
    else
      printf '  %s 切换选择  %s 全选  %s 全不选\n' \
        "$(ng_color "${NG_C_DIM}" "1-9")" \
        "$(ng_color "${NG_C_DIM}" "a")" \
        "$(ng_color "${NG_C_DIM}" "n")"
      printf '  %s 确认安装  %s 取消\n' \
        "$(ng_color "${NG_C_ACCENT}" "y")" \
        "$(ng_color "${NG_C_ACCENT}" "0")"
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
      u|U)
        if [[ "${do_update}" -eq 1 ]]; then
          do_update=0
        else
          do_update=1
        fi
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
            if [[ "${do_update}" -eq 1 ]]; then
              if [[ "${NG_LANG}" == "en" ]]; then
                printf 'Running apt update and upgrade...\n'
              else
                printf '正在执行 apt update 和 upgrade...\n'
              fi
              set +e
              apt-get update
              apt-get upgrade -y
              set -e
            fi
            local apt_output
            apt_output=$(apt-get install -y "${packages_to_install[@]}" 2>&1) || true
            printf '%s\n' "${apt_output}"
            
            # Check if apt suggests autoremove
            if [[ "${apt_output}" == *"no longer required"* ]]; then
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

ng_peer_count() {
  if [[ -f "${NG_NODES_FILE}" ]] && command -v jq >/dev/null 2>&1; then
    jq '[.servers[] | select(.enabled != false)] | length' "${NG_NODES_FILE}" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

ng_total_node_count() {
  local node_count
  node_count="$(ng_peer_count)"
  printf '%s\n' "$((node_count + 1))"
}

ng_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

ng_system_load() {
  uptime 2>/dev/null | awk -F'load average: ' '{print $2}' | tr -d '\r' || echo "unknown"
}

ng_get_cpu_usage() {
  local result=""
  if [[ -f /proc/stat ]]; then
    local cpu_line
    cpu_line=$(head -1 /proc/stat)
    local user nice system idle iowait irq softirq
    read -r _ user nice system idle iowait irq softirq _ <<< "${cpu_line}"
    local total=$((user + nice + system + idle + iowait + irq + softirq))
    local busy=$((user + nice + system + irq + softirq))
    if [[ "${total}" -gt 0 ]]; then
      result=$(awk "BEGIN {printf \"%.1f\", ${busy}/${total}*100}")
    else
      result="0.0"
    fi
  else
    set +e
    result=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    set -e
    result="${result:-0.0}"
  fi
  printf '%s' "${result}" | tr -d '[:space:]'
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

  cpu_usage=$(ng_get_cpu_usage | tr -d '\n' | cut -d'.' -f1)
  mem_usage=$(ng_get_memory_usage | tr -d '\n' | cut -d'.' -f1)
  disk_usage=$(ng_get_disk_usage | tr -d '\n')
  : "${cpu_usage:=0}"
  : "${mem_usage:=0}"
  : "${disk_usage:=0}"
  
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

ng_report_detail() {
  local label="$1"
  local value="$2"
  printf '%s  %s%-14s%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_PANEL}" "${label}:")" "" "${NG_C_RESET}" "${value}"
}

ng_report_separator() {
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "║")$(ng_color "${NG_C_PANEL_2}" " $(ng_repeat '─' 66)")"
}

ng_report_summary_start() {
  local title="$1"
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╠$(ng_repeat '─' 68)")"
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_BOLD}${NG_C_OK}" "📊 ${title}")"
}

ng_report_summary_kv() {
  local label="$1"
  local value="$2"
  printf '%s   %-14s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${label}" "${value}"
}

ng_report_advice_start() {
  local title="$1"
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╠$(ng_repeat '─' 68)")"
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_BOLD}${NG_C_ACCENT}" "💡 ${title}")"
}

ng_get_baseline_file() {
  local name="${1:-default}"
  printf '%s' "${NG_STATE_DIR}/integrity-${name}.sha256"
}

