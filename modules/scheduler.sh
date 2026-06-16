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
  printf 'Cron jobs installed.\n'
}

ng_show_cron_jobs() {
  crontab -l 2>/dev/null || printf 'No crontab entries found.\n'
}

ng_scheduler_menu() {
  local choice

  while true; do
    ng_print_header "Scheduler"
    cat <<'EOF'
1. Install recommended cron jobs
2. Show current crontab
0. Back
EOF
    printf 'Select: '
    read -r choice

    case "${choice}" in
      1) ng_install_cron_jobs ;;
      2) ng_show_cron_jobs ;;
      0) break ;;
      *) printf 'Invalid option.\n' ;;
    esac
  done
}
