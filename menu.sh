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
 cat <<'EOF'
==============================================================
 ServerHarbor
 Decentralized Multi-Server Bootstrap, Probe and Guard Toolkit
==============================================================
EOF
}

show_menu() {
  cat <<'EOF'
1. Server bootstrap
2. Peer probe and health report
3. Security audit and hardening
4. Backup and retention cleanup
5. File integrity baseline and verify
6. Git sync to remote
7. Install scheduled tasks
8. View latest reports
9. Project status summary
0. Exit
EOF
}

view_reports() {
  local latest_probe latest_security latest_backup latest_bootstrap

  latest_probe="$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f -name 'probe-*.txt' | sort | tail -n 1 || true)"
  latest_security="$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f -name 'security-*.txt' | sort | tail -n 1 || true)"
  latest_backup="$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f -name 'backup-*.txt' | sort | tail -n 1 || true)"
  latest_bootstrap="$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f -name 'bootstrap-*.txt' | sort | tail -n 1 || true)"

  for report_file in "$latest_bootstrap" "$latest_probe" "$latest_security" "$latest_backup"; do
    if [[ -n "${report_file}" && -f "${report_file}" ]]; then
      ng_print_header "Report: $(basename "${report_file}")"
      sed -n '1,120p' "${report_file}"
      printf '\n'
    fi
  done
}

status_summary() {
  ng_print_header "Project Status"
  printf 'Project root: %s\n' "${PROJECT_ROOT}"
  printf 'Config file : %s\n' "${NG_CONFIG_FILE}"
  printf 'Peers file  : %s\n' "${NG_PEERS_FILE}"
  printf 'Watch file  : %s\n' "${NG_WATCH_FILE}"
  printf 'Git branch  : %s\n' "$(ng_git_current_branch)"
  printf 'Git remote  : %s\n' "$(ng_git_remote_url)"
  printf 'State files : %s\n' "$(find "${NG_STATE_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  printf 'Reports     : %s\n' "$(find "${NG_REPORT_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  printf 'Backups     : %s\n' "$(find "${NG_BACKUP_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')"
}

main() {
  local choice

  while true; do
    show_banner
    show_menu
    printf '\nSelect an option: '
    read -r choice

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
      *) printf 'Invalid option.\n' ;;
    esac

    ng_press_enter
  done
}

run_cli_mode "${1:-}"
main "$@"
