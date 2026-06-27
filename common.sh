#!/usr/bin/env bash

set -euo pipefail

# --- 全局路径与运行时变量 ---
NG_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # 项目根目录
NG_HOSTNAME="$(hostname 2>/dev/null || echo unknown-host)"       # 当前主机名
NG_PROJECT_NAME="ServerHarbor"
NG_INSTALL_ROOT="/opt/serverharbor"                # 安装版根目录
NG_INSTALL_DATA="${NG_INSTALL_ROOT}/data"          # 安装版数据目录
NG_ONLINE_DATA="${SERVERHARBOR_HOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/serverharbor}"  # 在线版数据目录

# 判断运行模式：优先使用环境变量，其次检测安装标记，默认为在线模式
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

# --- 数据目录与配置路径 ---
NG_LANG="${SERVERHARBOR_LANG:-zh}"                 # 语言设置，默认中文
NG_LOG_DIR="${NG_DATA_ROOT}/logs"                  # 日志目录
NG_REPORT_DIR="${NG_DATA_ROOT}/reports"            # 报告目录
NG_STATE_DIR="${NG_DATA_ROOT}/state"               # 状态/基线目录
NG_CONFIG_FILE="${NG_DATA_ROOT}/serverharbor.conf" # 配置文件路径
NG_DEFAULT_CONFIG_DIR="${NG_PROJECT_ROOT}"         # 默认配置模板所在目录
NG_WATCH_PATHS=""               # 完整性监控默认路径

# --- 终端颜色变量（默认为空，由 ng_init_theme 填充） ---
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

# 检查指定目录是否包含有意义的数据（配置文件、状态、报告或日志）
ng_has_meaningful_data() {
  local dir="$1"
  [[ -f "${dir}/serverharbor.conf" ]] && return 0
  [[ -d "${dir}/state" ]] && [[ -n "$(ls -A "${dir}/state" 2>/dev/null)" ]] && return 0
  [[ -d "${dir}/reports" ]] && [[ -n "$(ls -A "${dir}/reports" 2>/dev/null)" ]] && return 0
  [[ -d "${dir}/logs" ]] && [[ -n "$(ls -A "${dir}/logs" 2>/dev/null)" ]] && return 0
  return 1
}

# 执行数据迁移：将源目录的配置和数据复制到目标目录，并重命名源目录
ng_do_migration() {
  local source_dir="$1"
  local target_dir="$2"
  local migrated_dir="$3"

  # 确保目标子目录存在
  mkdir -p "${target_dir}/state" "${target_dir}/logs" "${target_dir}/reports"

  local copied=0

  # 迁移配置文件
  for conf_name in serverharbor.conf; do
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

  # 迁移数据子目录（state、reports、logs）
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

  # 迁移完成后重命名源目录，避免重复迁移
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

# 触发数据迁移流程：仅在安装模式下可用，支持在线版↔安装版双向迁移
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

  # 检测两个位置是否各有数据
  local online_has_data=0
  local installed_has_data=0

  if [[ -d "${online_dir}" ]] && ng_has_meaningful_data "${online_dir}"; then
    online_has_data=1
  fi
  if [[ -d "${installed_dir}" ]] && ng_has_meaningful_data "${installed_dir}"; then
    installed_has_data=1
  fi

  # 两处都无数据
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

  # 仅在线版有数据 → 迁移到安装版
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

  # 仅安装版有数据，无需迁移
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

  # 两处都有数据，让用户选择迁移方向
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

# 初始化运行环境：创建目录、加载主题、读取配置文件
ng_init_environment() {
  mkdir -p "${NG_DATA_ROOT}" "${NG_LOG_DIR}" "${NG_REPORT_DIR}" "${NG_STATE_DIR}"

  ng_init_theme
  ng_seed_default_configs

  # 检测安装版与在线版同时运行的情况并提示用户
  if [[ "${NG_RUNTIME_MODE}" == "online" ]] && [[ -f "${NG_INSTALL_ROOT}/.serverharbor-install" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\n%s\n' "$(ng_color "${NG_C_WARN}" "⚠ ServerHarbor is installed but running in online mode.")"
      printf '  Installed data: %s\n' "${NG_INSTALL_DATA}"
      printf '  Online data:    %s\n' "${NG_ONLINE_DATA}"
      printf '  These are separate data stores. Use [1]→[6] in installed mode to merge.\n'
    else
      printf '\n%s\n' "$(ng_color "${NG_C_WARN}" "⚠ ServerHarbor 已安装，但当前运行在在线模式。")"
      printf '  安装版数据: %s\n' "${NG_INSTALL_DATA}"
      printf '  在线版数据: %s\n' "${NG_ONLINE_DATA}"
      printf '  两处数据独立，互不影响。如需合并请使用安装版菜单 [1]→[6]。\n'
    fi
  fi

  # 从配置文件加载 NG_ 开头的变量（安全过滤后写入）
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
      # 仅允许安全字符，防止配置注入
      if [[ "${_val}" =~ ^[a-zA-Z0-9_/.:~\ @,+-]*$ ]]; then
        printf -v "${_key}" '%s' "${_val}"
      fi
    done < "${NG_CONFIG_FILE}"
  fi

  # 设置各项默认值
  : "${NG_PROBE_TIMEOUT:=2}"
  : "${NG_ALERT_CPU_THRESHOLD:=80}"
  : "${NG_ALERT_MEM_THRESHOLD:=80}"
  : "${NG_ALERT_DISK_THRESHOLD:=90}"
  : "${NG_WATCH_PATHS:=/etc /var/www /root}"
}

# 初始化终端主题：检测是否支持颜色输出
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

# 给文本添加颜色（若终端支持）
ng_color() {
  local color="$1"
  shift
  if [[ "${NG_COLOR_ENABLED}" -eq 1 ]]; then
    printf '%s%s%s' "${color}" "$*" "${NG_C_RESET}"
  else
    printf '%s' "$*"
  fi
}

# 重复输出指定字符 N 次
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

# 打印带边框的标题盒子
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

# 打印菜单操作提示
ng_print_menu_hint() {
  printf '%s\n' "$(ng_color "${NG_C_DIM}" "$(ng_t menu_hint)")"
}

# 打印单个菜单选项（编号 + 图标 + 标签 + 可选描述）
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

# 打印统计信息行（图标 + 标签 + 值）
ng_print_stat() {
  local label="$1"
  local value="$2"
  local icon="${3:-•}"

  printf '  %s %-10s %s\n' \
    "$(ng_color "${NG_C_ACCENT_2}" "${icon}")" \
    "$(ng_color "${NG_C_DIM}" "${label}")" \
    "${value}"
}

# 报告底部边框
ng_report_footer() {
  local width=68
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╚$(ng_repeat '═' "${width}")")"
}

# 查询 systemd 服务运行状态
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

# 报告顶部标题栏
ng_report_header() {
  local title="$1"
  local width=68
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╔$(ng_repeat '═' "${width}")")"
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_BOLD}${NG_C_ACCENT}" "${title}")"
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╠$(ng_repeat '═' "${width}")")"
}

# 报告元信息行（键值对）
ng_report_meta() {
  local key="$1"
  local value="$2"
  printf '%s %-10s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_DIM}" "${key}")" "${value}"
}

# 报告分区标题
ng_report_section_start() {
  local title="$1"
  local width=68
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╠$(ng_repeat '─' "${width}")")"
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_BOLD}" "${title}")"
}

# 报告内容行
ng_report_line() {
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$1"
}

# 多语言文本翻译函数：根据 NG_LANG 返回对应语言的提示文本
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

# 从终端读取一行输入，存入指定变量
ng_read_line() {
  local __var_name="$1"
  local __value=""

  if ! IFS= read -r __value < /dev/tty; then
    ng_t interrupted >&2
    return 130
  fi

  printf -v "${__var_name}" '%s' "${__value}"
}

# 若数据目录中无配置文件，则从项目目录复制默认配置
ng_seed_default_configs() {
  if [[ ! -f "${NG_DATA_ROOT}/serverharbor.conf" && -f "${NG_DEFAULT_CONFIG_DIR}/serverharbor.conf" ]]; then
    cp "${NG_DEFAULT_CONFIG_DIR}/serverharbor.conf" "${NG_DATA_ROOT}/serverharbor.conf"
  fi
}

# 从配置文件中读取 __NODES__ 区段内的节点列表
ng_get_nodes() {
  if [[ ! -f "${NG_CONFIG_FILE}" ]]; then
    return 0
  fi
  if grep -q '^__NODES__$' "${NG_CONFIG_FILE}" 2>/dev/null; then
    sed -n '/^__NODES__$/,/^__NODES__$/{ /^__NODES__$/d; p; }' "${NG_CONFIG_FILE}" 2>/dev/null || true
  fi
}

# 向配置文件的 __NODES__ 区段追加一个新节点
ng_add_node_to_file() {
  local new_line="$1"
  local tmp="${NG_CONFIG_FILE}.tmp"
  if [[ ! -f "${NG_CONFIG_FILE}" ]]; then
    printf '# ServerHarbor Configuration\n\n__NODES__\n%s\n__NODES__\n' "${new_line}" > "${NG_CONFIG_FILE}"
    return 0
  fi

  if ! grep -q '^__NODES__$' "${NG_CONFIG_FILE}" 2>/dev/null; then
    printf '\n__NODES__\n%s\n__NODES__\n' "${new_line}" >> "${NG_CONFIG_FILE}"
    return 0
  fi

  # 保留 __NODES__ 之前的内容，重新拼接节点区段
  local existing
  existing=$(ng_get_nodes)
  sed '/^__NODES__$/,$d' "${NG_CONFIG_FILE}" > "${tmp}"
  {
    cat "${tmp}"
    printf '%s\n' "__NODES__"
    if [[ -n "${existing}" ]]; then
      printf '%s\n' "${existing}"
    fi
    printf '%s\n' "${new_line}"
    printf '%s\n' "__NODES__"
  } > "${NG_CONFIG_FILE}"
  rm -f "${tmp}"
}

# 从配置文件的 __NODES__ 区段删除指定名称的节点
ng_remove_node_from_file() {
  local name="$1"
  if [[ ! -f "${NG_CONFIG_FILE}" ]]; then
    return 0
  fi
  local tmp="${NG_CONFIG_FILE}.tmp"
  local existing
  existing=$(ng_get_nodes)
  # 按名称过滤，排除匹配行
  local filtered
  filtered=$(printf '%s\n' "${existing}" | awk -F'\t' -v name="${name}" '$1 != name' || true)
  sed '/^__NODES__$/,$d' "${NG_CONFIG_FILE}" > "${tmp}"
  {
    cat "${tmp}"
    printf '%s\n' "__NODES__"
    if [[ -n "${filtered}" ]]; then
      printf '%s\n' "${filtered}"
    fi
    printf '%s\n' "__NODES__"
  } > "${NG_CONFIG_FILE}"
  rm -f "${tmp}"
}

# 在配置文件中重命名节点
ng_rename_node_in_file() {
  local old_name="$1"
  local new_name="$2"
  if [[ ! -f "${NG_CONFIG_FILE}" ]]; then
    return 0
  fi
  local tmp="${NG_CONFIG_FILE}.tmp"
  local existing
  existing=$(ng_get_nodes)
  # 将匹配行的第一列（名称）替换为新名称
  local updated
  updated=$(printf '%s\n' "${existing}" | awk -F'\t' -v old="${old_name}" -v new="${new_name}" 'BEGIN{OFS="\t"} $1==old{$1=new} {print}')
  sed '/^__NODES__$/,$d' "${NG_CONFIG_FILE}" > "${tmp}"
  {
    cat "${tmp}"
    printf '%s\n' "__NODES__"
    if [[ -n "${updated}" ]]; then
      printf '%s\n' "${updated}"
    fi
    printf '%s\n' "__NODES__"
  } > "${NG_CONFIG_FILE}"
  rm -f "${tmp}"
}

# 统计已配置的节点数量
ng_peer_count() {
  local count=0
  local nodes_output
  nodes_output=$(ng_get_nodes)
  if [[ -n "${nodes_output}" ]]; then
    count=$(printf '%s\n' "${nodes_output}" | grep -c "	" 2>/dev/null || echo 0)
  fi
  count=$(printf '%d' "${count}" 2>/dev/null || echo 0)
  : "${count:=0}"
  printf '%s' "${count}"
}

# 计算总节点数（已配置节点 + 本机）
ng_total_node_count() {
  local node_count
  node_count="$(ng_peer_count)"
  printf '%s\n' "$((node_count + 1))"
}

# 按回车继续的通用提示
ng_press_enter() {
  ng_t press_enter
  ng_read_line _ || return 130
}

# 写日志：同时输出到终端和日志文件
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

# 是/否确认提示，返回 0 表示用户确认
ng_prompt_yes_no() {
  local prompt="$1"
  local answer

  printf '%s %s' "$(ng_color "${NG_C_WARN}" "${prompt}")" "$(ng_color "${NG_C_DIM}" '[y/N]: ')"
  ng_read_line answer || return 130
  [[ "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# 检查必要命令是否存在，缺失则报错
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

# 检查是否以 root 身份运行
ng_require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    ng_t requires_root
    return 1
  fi
}

# 检测系统包管理器类型
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

# 交互式安装基础软件包：支持多选、全选/全不选、apt update 等
ng_install_base_packages() {
  local manager
  manager="$(ng_detect_pkg_manager)"

  # 根据包管理器类型定义软件包列表
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
  
  # 默认选中：curl、wget、socat、sudo、iptables
  for ((i=0; i<pkg_count; i++)); do
    case $((i+1)) in
      1|2|7|8|9) selected+=(1) ;;
      *) selected+=(0) ;;
    esac
  done
  
  local do_update=1  # 默认执行 apt update/upgrade

  # 交互式选择循环
  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "📦 Package Installation" "Select packages to install"
    else
      ng_print_title_box "📦 软件包安装" "选择要安装的软件包"
    fi

    printf '\n'
    
    # 显示系统更新选项
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
    
    # 列出所有可选软件包
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
        # 切换是否执行系统更新
        if [[ "${do_update}" -eq 1 ]]; then
          do_update=0
        else
          do_update=1
        fi
        ;;
      [1-9])
        # 切换对应编号的软件包选中状态
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
        # 构建待安装列表
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

        # 执行包管理器安装命令
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
            
            # 检测是否有可自动清理的依赖包
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

# 获取当前时间戳
ng_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

# 获取系统负载（1/5/15 分钟）
ng_system_load() {
  uptime 2>/dev/null | awk -F'load average: ' '{print $2}' | tr -d '\r' || echo "unknown"
}

# 获取 CPU 使用率百分比（读取 /proc/stat 或 top）
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

# 获取内存使用率百分比
ng_get_memory_usage() {
  free 2>/dev/null | awk '/Mem:/ {printf "%.1f", $3/$2*100}' || echo "0"
}

# 获取根分区磁盘使用率百分比
ng_get_disk_usage() {
  df / 2>/dev/null | awk 'NR==2 {print $5}' | cut -d'%' -f1 || echo "0"
}

# 系统资源告警检测：CPU、内存、磁盘超过阈值时输出告警
ng_check_alerts() {
  local cpu_usage mem_usage disk_usage
  local alerts=()

  cpu_usage=$(ng_get_cpu_usage | tr -d '\n' | cut -d'.' -f1)
  mem_usage=$(ng_get_memory_usage | tr -d '\n' | cut -d'.' -f1)
  disk_usage=$(ng_get_disk_usage | tr -d '\n')
  : "${cpu_usage:=0}"
  : "${mem_usage:=0}"
  : "${disk_usage:=0}"
  
  # 检查 CPU
  if [[ "${cpu_usage}" -gt "${NG_ALERT_CPU_THRESHOLD}" ]]; then
    alerts+=("CPU: ${cpu_usage}% > ${NG_ALERT_CPU_THRESHOLD}%")
  fi
  
  # 检查内存
  if [[ "${mem_usage}" -gt "${NG_ALERT_MEM_THRESHOLD}" ]]; then
    alerts+=("Memory: ${mem_usage}% > ${NG_ALERT_MEM_THRESHOLD}%")
  fi
  
  # 检查磁盘
  if [[ "${disk_usage}" -gt "${NG_ALERT_DISK_THRESHOLD}" ]]; then
    alerts+=("Disk: ${disk_usage}% > ${NG_ALERT_DISK_THRESHOLD}%")
  fi
  
  # 输出告警
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

# 报告详情行（标签 + 值）
ng_report_detail() {
  local label="$1"
  local value="$2"
  printf '%s  %s%-14s%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_PANEL}" "${label}:")" "" "${NG_C_RESET}" "${value}"
}

# 报告分隔线
ng_report_separator() {
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "║")$(ng_color "${NG_C_PANEL_2}" " $(ng_repeat '─' 66)")"
}

# 报告摘要区域开始
ng_report_summary_start() {
  local title="$1"
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╠$(ng_repeat '─' 68)")"
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_BOLD}${NG_C_OK}" "📊 ${title}")"
}

# 报告摘要键值行
ng_report_summary_kv() {
  local label="$1"
  local value="$2"
  printf '%s   %-14s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${label}" "${value}"
}

# 报告建议区域开始
ng_report_advice_start() {
  local title="$1"
  printf '%s\n' "$(ng_color "${NG_C_PANEL}" "╠$(ng_repeat '─' 68)")"
  printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_BOLD}${NG_C_ACCENT}" "💡 ${title}")"
}

# 获取完整性基线文件路径
ng_get_baseline_file() {
  local name="${1:-default}"
  printf '%s' "${NG_STATE_DIR}/integrity-${name}.sha256"
}
