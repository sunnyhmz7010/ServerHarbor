#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=modules/bootstrap.sh
source "${PROJECT_ROOT}/modules/bootstrap.sh"
# shellcheck source=modules/probe.sh
source "${PROJECT_ROOT}/modules/probe.sh"
# shellcheck source=modules/security.sh
source "${PROJECT_ROOT}/modules/security.sh"
# shellcheck source=modules/monitor.sh
source "${PROJECT_ROOT}/modules/monitor.sh"
# shellcheck source=modules/network.sh
source "${PROJECT_ROOT}/modules/network.sh"

ng_init_environment

handle_menu_interrupt() {
  exit 130
}

trap handle_menu_interrupt INT

ng_is_online_runtime() {
  [[ "${SERVERHARBOR_RUNTIME:-}" == "online" ]]
}

ng_self_update_confirm() {
  if ng_is_online_runtime; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Online refresh will perform these actions:\n'
      printf '  1. Download the latest source archive from GitHub\n'
      printf '  2. Restart the current online session with the same data directory\n'
      printf '  3. Keep your existing configuration and reports\n'
      printf '  4. Do not write /opt or shortcut commands\n'
      printf 'Continue with online refresh? [Y/n]: '
    else
      printf '在线更新将执行以下操作：\n'
      printf '  1. 从 GitHub 下载最新源码压缩包\n'
      printf '  2. 使用相同数据目录重启当前在线会话\n'
      printf '  3. 保留现有配置与报告\n'
      printf '  4. 不写入 /opt，也不写入快捷命令\n'
      printf '是否继续在线更新？[Y/n]: '
    fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Update ServerHarbor will perform these actions:\n'
      printf '  1. Run the managed installer from the current local source tree\n'
      printf '  2. Download the latest source archive from GitHub for comparison/update\n'
      printf '  3. Preserve the existing data directory and configuration files\n'
      printf '  4. Skip replacement if the local code is already up to date\n'
      printf 'Continue with update? [y/N]: '
    else
      printf '更新 ServerHarbor 将执行以下操作：\n'
      printf '  1. 调用当前本地源码中的受管安装器\n'
      printf '  2. 从 GitHub 下载最新源码压缩包进行比对与更新\n'
      printf '  3. 保留现有数据目录与配置文件\n'
      printf '  4. 如果本地代码已是最新，则跳过替换\n'
      printf '是否继续更新？[y/N]: '
    fi
  fi
}

ng_self_update() {
  local installer="${PROJECT_ROOT}/install.sh"
  local answer=""

  if [[ ! -f "${installer}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "install.sh not found. Unable to run managed update."
    else
      ng_log "ERROR" "未找到 install.sh，无法执行受管更新。"
    fi
    return 1
  fi

  ng_self_update_confirm
  if ! ng_read_line answer; then
    return 130
  fi
  if [[ -n "${answer}" && ! "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "Update cancelled."
    else
      ng_log "WARN" "已取消更新。"
    fi
    return 0
  fi

  if ng_is_online_runtime; then
    printf 'DEBUG: Exiting with code %s\n' "${SERVERHARBOR_REFRESH_EXIT_CODE:-42}" >&2
    exit "${SERVERHARBOR_REFRESH_EXIT_CODE:-42}"
  fi

  chmod +x "${installer}" 2>/dev/null || true
  bash "${installer}"
}

run_cli_mode() {
  case "${1:-}" in
    --cron-probe)
      ng_probe_all_peers
      exit 0
      ;;
    --cron-security)
      ng_security_report
      exit 0
      ;;
    "")
      return 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1"
      exit 1
      ;;
  esac
}

show_banner() {
  clear || true

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_title_box "🚢 ServerHarbor" "Decentralized multi-server bootstrap, probe and security toolkit"
    ng_print_stat "Host" "${NG_HOSTNAME}" "🖥"
    ng_print_stat "Data Root" "${NG_DATA_ROOT}" "📦"
    ng_print_stat "Reports" "$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')" "📄"
    ng_print_stat "Total Nodes" "$(ng_total_node_count)" "🛰"
  else
    ng_print_title_box "🚢 ServerHarbor" "去中心化多服务器开荒、探测与安全工具箱"
    ng_print_stat "主机" "${NG_HOSTNAME}" "🖥"
    ng_print_stat "数据目录" "${NG_DATA_ROOT}" "📦"
    ng_print_stat "报告数" "$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')" "📄"
    ng_print_stat "总节点数" "$(ng_total_node_count)" "🛰"
  fi

  printf '\n'
}

show_menu() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_option "1" "🚀" "Server bootstrap" "DNS / swap / BBR / base packages / SSH hardening"
    ng_print_option "2" "🛰" "Peer probe and health report" "Local snapshot and peer reachability checks"
    ng_print_option "3" "🛡" "Security audit and hardening" "Auth logs, suspicious traffic, firewall and integrity checks"
    ng_print_option "4" "📊" "System monitor" "Real-time CPU, memory, disk monitoring and alerts"
    ng_print_option "5" "🌐" "Network tools" "Ping, traceroute, DNS lookup, port scan, bandwidth test"
    if ng_is_online_runtime; then
      ng_print_option "6" "♻️" "Refresh online session" "Re-download latest source and restart this temporary session"
    else
      ng_print_option "6" "♻️" "Update ServerHarbor" "Run managed installer update without replacing your data root"
    fi
    ng_print_option "0" "↩" "Exit"
  else
    ng_print_option "1" "🚀" "新服务器开荒" "DNS / swap / BBR / 基础软件 / SSH 加固"
    ng_print_option "2" "🛰" "节点探测与健康报告" "本机快照与节点连通性检查"
    ng_print_option "3" "🛡" "安全巡检与基础加固" "认证日志、可疑流量、防火墙与完整性校验"
    ng_print_option "4" "📊" "系统监控" "实时 CPU、内存、磁盘监控与告警"
    ng_print_option "5" "🌐" "网络工具" "Ping、路由追踪、DNS 查询、端口扫描、带宽测试"
    if ng_is_online_runtime; then
      ng_print_option "6" "♻️" "在线更新当前会话" "重新拉取最新源码并重启当前临时会话"
    else
      ng_print_option "6" "♻️" "更新 ServerHarbor" "调用受管安装器更新代码，不覆盖数据目录"
    fi
    ng_print_option "0" "↩" "退出"
  fi

  printf '\n'
  ng_print_menu_hint
}

main() {
  local choice

  while true; do
    show_banner
    show_menu
    printf '\n'
    ng_t select
    ng_read_line choice || exit 130

    case "${choice}" in
      1) ng_bootstrap_menu ;;
      2) ng_probe_menu ;;
      3) ng_security_menu ;;
      4) ng_monitor_menu ;;
      5) ng_network_menu ;;
      6) ng_self_update ;;
      0) exit 0 ;;
      *) ng_t invalid_option ;;
    esac
  done
}

run_cli_mode "${1:-}"
main "$@"
