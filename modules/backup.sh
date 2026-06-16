#!/usr/bin/env bash

set -euo pipefail

ng_backup_paths() {
  [[ -f "${NG_WATCH_FILE}" ]] || return 0
  grep -Ev '^\s*#|^\s*$' "${NG_WATCH_FILE}"
}

ng_create_backup_archive() {
  local archive_name="${NG_BACKUP_DIR}/${NG_HOSTNAME}-backup-$(date '+%Y%m%d-%H%M%S').tar.gz"
  local paths=()
  local path

  while IFS= read -r path; do
    [[ -e "${path}" ]] && paths+=("${path}")
  done < <(ng_backup_paths)

  if [[ "${#paths[@]}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No valid backup paths found.\n'; else printf '未找到有效备份路径。\n'; fi
    return 1
  fi

  tar -czf "${archive_name}" "${paths[@]}"
  if [[ "${NG_LANG}" == "en" ]]; then printf 'Backup archive created: %s\n' "${archive_name}"; else printf '备份压缩包已创建：%s\n' "${archive_name}"; fi
}

ng_backup_cleanup() {
  find "${NG_BACKUP_DIR}" -type f -mtime +"${NG_BACKUP_RETENTION_DAYS}" -delete
  if [[ "${NG_LANG}" == "en" ]]; then printf 'Old backups older than %s days removed.\n' "${NG_BACKUP_RETENTION_DAYS}"; else printf '已删除超过 %s 天的旧备份。\n' "${NG_BACKUP_RETENTION_DAYS}"; fi
}

ng_backup_sync_to_peer() {
  local latest_archive peer_alias peer_host

  latest_archive="$(find "${NG_BACKUP_DIR}" -maxdepth 1 -type f -name '*.tar.gz' | sort | tail -n 1 || true)"
  [[ -n "${latest_archive}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No backup archive found. Create one first.\n'; else printf '未找到备份压缩包，请先创建备份。\n'; fi
    return 1
  }

  while IFS=',' read -r peer_alias peer_host; do
    [[ -n "${peer_alias}" && -n "${peer_host}" ]] || continue
    if [[ "${NG_LANG}" == "en" ]]; then printf 'Syncing %s to %s (%s)\n' "$(basename "${latest_archive}")" "${peer_alias}" "${peer_host}"; else printf '正在同步 %s 到 %s（%s）\n' "$(basename "${latest_archive}")" "${peer_alias}" "${peer_host}"; fi
    rsync -avz -e ssh "${latest_archive}" "root@${peer_host}:/var/backups/" || true
  done < <(ng_read_peers)
}

ng_backup_report() {
  local content

  content="$(
    printf 'ServerHarbor Backup Report\n'
    ng_t generated_at "$(ng_timestamp)"
    printf 'Host        : %s\n' "${NG_HOSTNAME}"
    printf 'Retention   : %s days\n\n' "${NG_BACKUP_RETENTION_DAYS}"
    printf '[Backup Directory]\n'
    ls -lh "${NG_BACKUP_DIR}" 2>/dev/null || true
  )"

  ng_write_report "backup" "${content}" >/dev/null
  printf '%s\n' "${content}"
}

ng_backup_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "Backup Guard"
      cat <<'EOF'
1. Create backup archive
2. Cleanup expired backups
3. Sync latest backup to peers
4. Generate backup report
0. Back
EOF
    else
      ng_print_header "备份管理"
      cat <<'EOF'
1. 创建备份压缩包
2. 清理过期备份
3. 同步最新备份到节点
4. 生成备份报告
0. 返回
EOF
    fi
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_create_backup_archive ;;
      2) ng_backup_cleanup ;;
      3) ng_backup_sync_to_peer ;;
      4) ng_backup_report ;;
      0) break ;;
      *) ng_t invalid_option ;;
    esac
  done
}
