#!/usr/bin/env bash

set -euo pipefail

ng_cron_entry() {
  local schedule="$1"
  local command="$2"
  printf '%s %s\n' "${schedule}" "${command}"
}

ng_install_cron_jobs() {
  ng_require_cmd crontab || return 1

  local menu_script="${NG_PROJECT_ROOT}/menu.sh"
  local probe_cmd="/bin/bash ${menu_script} --cron-probe"
  local security_cmd="/bin/bash ${menu_script} --cron-security"
  local backup_cmd="/bin/bash ${menu_script} --cron-backup"
  local git_cmd="/bin/bash ${menu_script} --cron-git"
  local current_cron new_cron

  current_cron="$(crontab -l 2>/dev/null || true)"
  new_cron="$(
    printf '%s\n' "${current_cron}"
    ng_cron_entry "*/10 * * * *" "${probe_cmd} >> ${NG_LOG_DIR}/cron-probe.log 2>&1"
    ng_cron_entry "30 * * * *" "${security_cmd} >> ${NG_LOG_DIR}/cron-security.log 2>&1"
    ng_cron_entry "0 2 * * *" "${backup_cmd} >> ${NG_LOG_DIR}/cron-backup.log 2>&1"
    ng_cron_entry "*/30 * * * *" "${git_cmd} >> ${NG_LOG_DIR}/cron-git.log 2>&1"
  )"

  printf '%s\n' "${new_cron}" | awk '!seen[$0]++' | crontab -
  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Cron jobs installed.\n'
  else
    printf '定时任务已安装。\n'
  fi
}

ng_show_cron_jobs() {
  crontab -l 2>/dev/null || {
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No crontab entries found.\n'
    else
      printf '未找到 crontab 条目。\n'
    fi
  }
}

ng_scheduler_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "⏱ Scheduler" "Install and inspect recommended recurring jobs"
      ng_print_option "1" "📌" "Install recommended cron jobs" "Probe, security, backup and git sync routines"
      ng_print_option "2" "📜" "Show current crontab" "Inspect all existing scheduled tasks"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "⏱ 定时任务" "安装并查看推荐的周期性任务"
      ng_print_option "1" "📌" "安装推荐 cron 任务" "包含探测、安全、备份与 Git 同步例程"
      ng_print_option "2" "📜" "查看当前 crontab" "检查现有全部计划任务"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_install_cron_jobs ;;
      2) ng_show_cron_jobs ;;
      0) break ;;
      *) ng_t invalid_option ;;
    esac
  done
}
