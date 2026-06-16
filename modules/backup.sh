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
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No valid backup paths found.\n'
    else
      printf '未找到有效备份路径。\n'
    fi
    return 1
  fi

  tar -czf "${archive_name}" "${paths[@]}"
  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Backup archive created: %s\n' "${archive_name}"
  else
    printf '备份压缩包已创建：%s\n' "${archive_name}"
  fi
}

ng_backup_cleanup() {
  find "${NG_BACKUP_DIR}" -type f -mtime +"${NG_BACKUP_RETENTION_DAYS}" -delete
  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Old backups older than %s days removed.\n' "${NG_BACKUP_RETENTION_DAYS}"
  else
    printf '已删除超过 %s 天的旧备份。\n' "${NG_BACKUP_RETENTION_DAYS}"
  fi
}

ng_backup_sync_to_peer() {
  local latest_archive peer_alias peer_host

  latest_archive="$(find "${NG_BACKUP_DIR}" -maxdepth 1 -type f -name '*.tar.gz' | sort | tail -n 1 || true)"
  [[ -n "${latest_archive}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No backup archive found. Create one first.\n'
    else
      printf '未找到备份压缩包，请先创建备份。\n'
    fi
    return 1
  }

  while IFS=',' read -r peer_alias peer_host; do
    [[ -n "${peer_alias}" && -n "${peer_host}" ]] || continue
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Syncing %s to %s (%s)\n' "$(basename "${latest_archive}")" "${peer_alias}" "${peer_host}"
    else
      printf '正在同步 %s 到 %s（%s）\n' "$(basename "${latest_archive}")" "${peer_alias}" "${peer_host}"
    fi
    rsync -avz -e ssh "${latest_archive}" "root@${peer_host}:/var/backups/" || true
  done < <(ng_read_peers)
}

ng_backup_report() {
  local content

  if [[ "${NG_LANG}" == "en" ]]; then
    content="$(
      printf 'ServerHarbor Backup Report\n'
      ng_t generated_at "$(ng_timestamp)"
      printf 'Host        : %s\n' "${NG_HOSTNAME}"
      printf 'Retention   : %s days\n\n' "${NG_BACKUP_RETENTION_DAYS}"
      printf '[Backup Directory]\n'
      ls -lh "${NG_BACKUP_DIR}" 2>/dev/null || true
    )"
  else
    content="$(
      printf 'ServerHarbor 备份报告\n'
      ng_t generated_at "$(ng_timestamp)"
      printf '主机        : %s\n' "${NG_HOSTNAME}"
      printf '保留天数    : %s 天\n\n' "${NG_BACKUP_RETENTION_DAYS}"
      printf '[备份目录]\n'
      ls -lh "${NG_BACKUP_DIR}" 2>/dev/null || true
    )"
  fi

  ng_write_report "backup" "${content}" >/dev/null
  printf '%s\n' "${content}"
}

ng_backup_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "💾 Backup Guard" "Archive, prune and distribute backup packages"
      ng_print_option "1" "📦" "Create backup archive" "Compress all valid paths listed in watch.conf"
      ng_print_option "2" "🧹" "Cleanup expired backups" "Delete old backup archives by retention days"
      ng_print_option "3" "🔄" "Sync latest backup to peers" "Send the latest archive to configured peers via rsync"
      ng_print_option "4" "📄" "Generate backup report" "List retention policy and current backup directory"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "💾 备份管理" "归档、清理并分发备份压缩包"
      ng_print_option "1" "📦" "创建备份压缩包" "压缩 watch.conf 中存在的有效路径"
      ng_print_option "2" "🧹" "清理过期备份" "按保留天数删除旧备份压缩包"
      ng_print_option "3" "🔄" "同步最新备份到节点" "通过 rsync 将最新压缩包发往已配置节点"
      ng_print_option "4" "📄" "生成备份报告" "查看保留策略与当前备份目录内容"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
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
