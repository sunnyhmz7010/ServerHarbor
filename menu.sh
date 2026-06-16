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

ng_init_environment

handle_menu_interrupt() {
  ng_t interrupted >&2
  exit 130
}

trap handle_menu_interrupt INT

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
    ng_print_option "0" "↩" "Exit"
  else
    ng_print_option "1" "🚀" "新服务器开荒" "DNS / swap / BBR / 基础软件 / SSH 加固"
    ng_print_option "2" "🛰" "节点探测与健康报告" "本机快照与节点连通性检查"
    ng_print_option "3" "🛡" "安全巡检与基础加固" "认证日志、可疑流量、防火墙与完整性校验"
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
      0) exit 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || exit 130
  done
}

run_cli_mode "${1:-}"
main "$@"
