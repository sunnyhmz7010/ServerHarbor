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
  if [[ "${NG_LANG}" == "en" ]]; then printf 'Cron jobs installed.\n'; else printf '定时任务已安装。\n'; fi
}

ng_show_cron_jobs() {
  crontab -l 2>/dev/null || { if [[ "${NG_LANG}" == "en" ]]; then printf 'No crontab entries found.\n'; else printf '未找到 crontab 条目。\n'; fi; }
}

ng_scheduler_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "Scheduler"
      cat <<'EOF'
1. Install recommended cron jobs
2. Show current crontab
0. Back
EOF
    else
      ng_print_header "定时任务"
      cat <<'EOF'
1. 安装推荐的 cron 任务
2. 查看当前 crontab
0. 返回
EOF
    fi
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
