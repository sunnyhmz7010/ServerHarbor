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
# shellcheck source=modules/backup.sh
source "${PROJECT_ROOT}/modules/backup.sh"
# shellcheck source=modules/git_sync.sh
source "${PROJECT_ROOT}/modules/git_sync.sh"
# shellcheck source=modules/scheduler.sh
source "${PROJECT_ROOT}/modules/scheduler.sh"

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
    --cron-backup)
      ng_create_backup_archive || true
      ng_backup_cleanup
      ng_backup_report
      exit 0
      ;;
    --cron-git)
      ng_git_auto_sync
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
    ng_print_title_box "🚢 ServerHarbor" "Decentralized multi-server bootstrap, probe, backup and security toolkit"
    ng_print_stat "Host" "${NG_HOSTNAME}" "🖥"
    ng_print_stat "Data Root" "${NG_DATA_ROOT}" "📦"
    ng_print_stat "Reports" "$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')" "📄"
    ng_print_stat "Peers" "$(ng_read_peers | wc -l | tr -d ' ')" "🛰"
  else
    ng_print_title_box "🚢 ServerHarbor" "去中心化多服务器开荒、探测、备份与安全工具箱"
    ng_print_stat "主机" "${NG_HOSTNAME}" "🖥"
    ng_print_stat "数据目录" "${NG_DATA_ROOT}" "📦"
    ng_print_stat "报告数" "$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')" "📄"
    ng_print_stat "节点数" "$(ng_read_peers | wc -l | tr -d ' ')" "🛰"
  fi

  printf '\n'
}

show_menu() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_option "1" "🚀" "Server bootstrap" "DNS / swap / BBR / base packages / SSH hardening"
    ng_print_option "2" "🛰" "Peer probe and health report" "Local snapshot and peer reachability checks"
    ng_print_option "3" "🛡" "Security audit and hardening" "Auth logs, suspicious traffic and firewall"
    ng_print_option "4" "💾" "Backup and retention cleanup" "Create, prune and sync backup archives"
    ng_print_option "5" "🧬" "Integrity baseline and verify" "Create and verify watched file hashes"
    ng_print_option "6" "🌿" "Git sync to remote" "Commit current state and push to GitHub"
    ng_print_option "7" "⏱" "Install scheduled tasks" "Recommended cron tasks for routine jobs"
    ng_print_option "8" "📚" "View latest reports" "Preview recent bootstrap, probe, security and backup reports"
    ng_print_option "9" "📊" "Project status summary" "Paths, branch, remote, reports and backup counts"
    ng_print_option "0" "↩" "Exit"
  else
    ng_print_option "1" "🚀" "新服务器开荒" "DNS / swap / BBR / 基础软件 / SSH 加固"
    ng_print_option "2" "🛰" "节点探测与健康报告" "本机快照与节点连通性检查"
    ng_print_option "3" "🛡" "安全巡检与基础加固" "认证日志、可疑流量与防火墙"
    ng_print_option "4" "💾" "备份与保留清理" "创建、清理并同步备份压缩包"
    ng_print_option "5" "🧬" "完整性基线与校验" "生成并校验受监控文件哈希"
    ng_print_option "6" "🌿" "Git 远端同步" "提交当前状态并推送到 GitHub"
    ng_print_option "7" "⏱" "安装定时任务" "为常规巡检安装推荐 cron 任务"
    ng_print_option "8" "📚" "查看最新报告" "预览开荒、探测、安全和备份报告"
    ng_print_option "9" "📊" "项目状态摘要" "查看路径、分支、远端与报告统计"
    ng_print_option "0" "↩" "退出"
  fi

  printf '\n'
  ng_print_menu_hint
}

view_reports() {
  local latest_probe latest_security latest_backup latest_bootstrap
  local found=0

  latest_probe="$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f -name 'probe-*.txt' | sort | tail -n 1 || true)"
  latest_security="$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f -name 'security-*.txt' | sort | tail -n 1 || true)"
  latest_backup="$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f -name 'backup-*.txt' | sort | tail -n 1 || true)"
  latest_bootstrap="$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f -name 'bootstrap-*.txt' | sort | tail -n 1 || true)"

  for report_file in "${latest_bootstrap}" "${latest_probe}" "${latest_security}" "${latest_backup}"; do
    if [[ -n "${report_file}" && -f "${report_file}" ]]; then
      found=1
      if [[ "${NG_LANG}" == "en" ]]; then
        ng_print_header "Report: $(basename "${report_file}")"
      else
        ng_print_header "报告：$(basename "${report_file}")"
      fi
      sed -n '1,120p' "${report_file}"
      printf '\n'
    fi
  done

  if [[ "${found}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "No reports found yet."
    else
      ng_log "WARN" "暂未找到任何报告。"
    fi
  fi
}

status_summary() {
  local state_count report_count backup_count

  state_count="$(find "${NG_STATE_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  report_count="$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  backup_count="$(find "${NG_BACKUP_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_title_box "📊 Project Status" "Runtime paths and repository summary"
    ng_print_stat "Project Root" "${PROJECT_ROOT}" "📁"
    ng_print_stat "Config File" "${NG_CONFIG_FILE}" "⚙"
    ng_print_stat "Peers File" "${NG_PEERS_FILE}" "🛰"
    ng_print_stat "Watch File" "${NG_WATCH_FILE}" "👁"
    ng_print_stat "Git Branch" "$(ng_git_current_branch)" "🌿"
    ng_print_stat "Git Remote" "$(ng_git_remote_url)" "🔗"
    ng_print_stat "State Files" "${state_count}" "🧾"
    ng_print_stat "Reports" "${report_count}" "📄"
    ng_print_stat "Backups" "${backup_count}" "💾"
  else
    ng_print_title_box "📊 项目状态" "运行路径与仓库状态摘要"
    ng_print_stat "项目根目录" "${PROJECT_ROOT}" "📁"
    ng_print_stat "配置文件" "${NG_CONFIG_FILE}" "⚙"
    ng_print_stat "节点列表" "${NG_PEERS_FILE}" "🛰"
    ng_print_stat "监控路径" "${NG_WATCH_FILE}" "👁"
    ng_print_stat "Git 分支" "$(ng_git_current_branch)" "🌿"
    ng_print_stat "Git 远端" "$(ng_git_remote_url)" "🔗"
    ng_print_stat "状态文件" "${state_count}" "🧾"
    ng_print_stat "报告数量" "${report_count}" "📄"
    ng_print_stat "备份数量" "${backup_count}" "💾"
  fi
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
      4) ng_backup_menu ;;
      5) ng_integrity_menu ;;
      6) ng_git_sync_menu ;;
      7) ng_scheduler_menu ;;
      8) view_reports ;;
      9) status_summary ;;
      0) exit 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || exit 130
  done
}

run_cli_mode "${1:-}"
main "$@"
