#!/usr/bin/env bash

set -euo pipefail

ng_collect_local_probe() {
  local state_file="${NG_STATE_DIR}/${NG_HOSTNAME}-local.state"
  local tmp_file="${state_file}.tmp"

  {
    printf 'timestamp=%s\n' "$(date '+%s')"
    printf 'host=%s\n' "${NG_HOSTNAME}"
    printf 'uptime=%s\n' "$(uptime -p 2>/dev/null || uptime)"
    printf 'load=%s\n' "$(ng_system_load)"
    printf 'disk_root=%s\n' "$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' || echo unknown)"
    printf 'mem_used=%s\n' "$(free -m 2>/dev/null | awk '/Mem:/ {printf "%s/%sMB", $3, $2}' || echo unknown)"
    printf 'ssh=%s\n' "$(ng_service_state sshd)"
  } > "${tmp_file}"

  # Atomic move to ensure data integrity
  if mv -f "${tmp_file}" "${state_file}" 2>/dev/null; then
    printf '%s\n' "${state_file}"
  else
    rm -f "${tmp_file}" 2>/dev/null
    ng_log "ERROR" "Failed to write state file"
    return 1
  fi
}

ng_probe_single_peer() {
  local peer_host="$1"
  local peer_alias="$2"
  local ping_result ssh_result latency
  local ping_output

  ping_output="$(ping -c 1 -W "${NG_PROBE_TIMEOUT}" "${peer_host}" 2>/dev/null)" || true
  
  if [[ -n "${ping_output}" ]] && echo "${ping_output}" | grep -q "bytes from"; then
    ping_result="up"
    latency="$(echo "${ping_output}" | awk -F'time=' 'END {print $2}' | awk '{print $1}' || echo n/a)"
  else
    ping_result="down"
    latency="timeout"
  fi

  # Try nc first, fallback to /dev/tcp
  if nc -z -w "${NG_PROBE_TIMEOUT}" "${peer_host}" 22 2>/dev/null; then
    ssh_result="open"
  elif timeout "${NG_PROBE_TIMEOUT}" bash -c "cat < /dev/null > /dev/tcp/${peer_host}/22" >/dev/null 2>&1; then
    ssh_result="open"
  else
    ssh_result="closed"
  fi

  printf '%-16s %-24s %-8s %-10s %s\n' "${peer_alias}" "${peer_host}" "${ping_result}" "${ssh_result}" "${latency}"
}

ng_probe_all_peers() {
  local output_file="${NG_STATE_DIR}/${NG_HOSTNAME}-peers.state"

  {
    printf 'Peer Alias       Peer Host                ICMP     SSH Port   Latency\n'
    printf '%s\n' '---------------------------------------------------------------------'
    while IFS=',' read -r peer_alias peer_host; do
      [[ -n "${peer_alias}" && -n "${peer_host}" ]] || continue
      ng_probe_single_peer "${peer_host}" "${peer_alias}"
    done < <(ng_read_peers)
  } | tee "${output_file}"

  # Collect local probe once
  local state_file
  state_file="$(ng_collect_local_probe)"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🛰 ServerHarbor Probe Report"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "Peer Matrix"
    cat "${output_file}" | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_section_start "Local Snapshot"
    cat "${state_file}" | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_footer
  else
    ng_report_header "🛰 ServerHarbor 节点探测报告"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "节点矩阵"
    cat "${output_file}" | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_section_start "本机快照"
    cat "${state_file}" | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_footer
  fi
}

ng_local_health() {
  local state_file
  state_file="$(ng_collect_local_probe)"
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "Local Health Status"
    ng_report_meta "Hostname" "${NG_HOSTNAME}"
    ng_report_meta "Collected At" "$(ng_timestamp)"
    ng_report_section_start "System Info"
    ng_report_kv_styled "Uptime" "$(uptime -p 2>/dev/null || uptime)"
    ng_report_kv_styled "System Load" "$(ng_system_load)"
    ng_report_section_start "Resource Usage"
    ng_report_kv_styled "Memory" "$(free -m 2>/dev/null | awk '/Mem:/ {printf "%s/%sMB (%.1f%%)", $3, $2, $3/$2*100}' || echo unknown)"
    ng_report_kv_styled "Disk /" "$(df -h / 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}' || echo unknown)"
    ng_report_section_start "Network Ports"
    ng_report_line "Listening ports:"
    ss -lntp 2>/dev/null | sed -n '1,15p' | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_footer
    printf '\n'
    printf 'State saved to: %s\n' "${state_file}"
  else
    ng_report_header "本机健康状态"
    ng_report_meta "主机名" "${NG_HOSTNAME}"
    ng_report_meta "采集时间" "$(ng_timestamp)"
    ng_report_section_start "系统信息"
    ng_report_kv_styled "运行时长" "$(uptime -p 2>/dev/null || uptime)"
    ng_report_kv_styled "系统负载" "$(ng_system_load)"
    ng_report_section_start "资源使用"
    ng_report_kv_styled "内存" "$(free -m 2>/dev/null | awk '/Mem:/ {printf "%s/%sMB (%.1f%%)", $3, $2, $3/$2*100}' || echo unknown)"
    ng_report_kv_styled "磁盘 /" "$(df -h / 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}' || echo unknown)"
    ng_report_section_start "网络端口"
    ng_report_line "监听端口:"
    ss -lntp 2>/dev/null | sed -n '1,15p' | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_footer
    printf '\n'
    printf '状态已保存至: %s\n' "${state_file}"
  fi
}

ng_view_logs() {
  local log_type="$1"
  local log_file=""

  case "${log_type}" in
    auth)
      if [[ -f /var/log/auth.log ]]; then
        log_file="/var/log/auth.log"
      elif [[ -f /var/log/secure ]]; then
        log_file="/var/log/secure"
      fi
      ;;
    syslog)
      if [[ -f /var/log/syslog ]]; then
        log_file="/var/log/syslog"
      elif [[ -f /var/log/messages ]]; then
        log_file="/var/log/messages"
      fi
      ;;
    dmesg)
      log_file="dmesg"
      ;;
    *)
      if [[ "${NG_LANG}" == "en" ]]; then
        ng_log "ERROR" "Unknown log type: ${log_type}"
      else
        ng_log "ERROR" "未知日志类型: ${log_type}"
      fi
      return 1
      ;;
  esac

  if [[ "${log_type}" == "dmesg" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "Kernel Messages (dmesg)"
    else
      ng_print_header "内核消息 (dmesg)"
    fi
    dmesg | tail -50
  elif [[ -n "${log_file}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "Log: ${log_file}"
      printf 'Showing last 50 lines:\n\n'
    else
      ng_print_header "日志: ${log_file}"
      printf '显示最后 50 行:\n\n'
    fi
    tail -50 "${log_file}"
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "Log file not found for type: ${log_type}"
    else
      ng_log "ERROR" "未找到类型为 ${log_type} 的日志文件"
    fi
    return 1
  fi
}

ng_backup_manager() {
  local backup_dir="${NG_DATA_ROOT}/backups"
  mkdir -p "${backup_dir}"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Backup Management"
    printf 'Backup directory: %s\n\n' "${backup_dir}"
    printf '  [1] Backup configuration files\n'
    printf '  [2] Backup state files\n'
    printf '  [3] List existing backups\n'
    printf '  [4] Restore from backup\n'
    printf '  [0] Back\n'
  else
    ng_print_header "备份管理"
    printf '备份目录: %s\n\n' "${backup_dir}"
    printf '  [1] 备份配置文件\n'
    printf '  [2] 备份状态文件\n'
    printf '  [3] 列出现有备份\n'
    printf '  [4] 从备份恢复\n'
    printf '  [0] 返回\n'
  fi

  local choice
  ng_read_line choice || return 130

  case "${choice}" in
    1)
      local backup_file="${backup_dir}/config-$(date '+%Y%m%d-%H%M%S').tar.gz"
      tar -czf "${backup_file}" -C "${NG_DATA_ROOT}" config 2>/dev/null
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Configuration backed up to: %s\n' "${backup_file}"
      else
        printf '配置已备份至: %s\n' "${backup_file}"
      fi
      ;;
    2)
      local backup_file="${backup_dir}/state-$(date '+%Y%m%d-%H%M%S').tar.gz"
      tar -czf "${backup_file}" -C "${NG_DATA_ROOT}" state 2>/dev/null
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'State files backed up to: %s\n' "${backup_file}"
      else
        printf '状态文件已备份至: %s\n' "${backup_file}"
      fi
      ;;
    3)
      if [[ "${NG_LANG}" == "en" ]]; then
        ng_print_header "Existing Backups"
        ls -lh "${backup_dir}"/*.tar.gz 2>/dev/null || printf 'No backups found.\n'
      else
        ng_print_header "现有备份"
        ls -lh "${backup_dir}"/*.tar.gz 2>/dev/null || printf '未找到备份文件。\n'
      fi
      ;;
    4)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Available backups:\n'
        ls -1 "${backup_dir}"/*.tar.gz 2>/dev/null || printf 'No backups found.\n'
        printf '\nEnter backup file path to restore: '
      else
        printf '可用备份:\n'
        ls -1 "${backup_dir}"/*.tar.gz 2>/dev/null || printf '未找到备份文件。\n'
        printf '\n输入要恢复的备份文件路径: '
      fi
      local restore_file
      ng_read_line restore_file || return 130
      
      if [[ -f "${restore_file}" ]]; then
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Restoring from: %s\n' "${restore_file}"
        else
          printf '正在从 %s 恢复\n' "${restore_file}"
        fi
        tar -xzf "${restore_file}" -C "${NG_DATA_ROOT}" 2>/dev/null
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Restore completed.\n'
        else
          printf '恢复完成。\n'
        fi
      else
        if [[ "${NG_LANG}" == "en" ]]; then
          ng_log "ERROR" "Backup file not found: ${restore_file}"
        else
          ng_log "ERROR" "备份文件不存在: ${restore_file}"
        fi
      fi
      ;;
    0) return 0 ;;
    *)
      ng_t invalid_option
      ;;
  esac
}
