#!/usr/bin/env bash

set -euo pipefail

ng_collect_local_probe() {
  local state_file="${NG_STATE_DIR}/${NG_HOSTNAME}-local.state"

  {
    printf 'timestamp=%s\n' "$(date '+%s')"
    printf 'host=%s\n' "${NG_HOSTNAME}"
    printf 'uptime=%s\n' "$(uptime -p 2>/dev/null || uptime)"
    printf 'load=%s\n' "$(ng_system_load)"
    printf 'disk_root=%s\n' "$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' || echo unknown)"
    printf 'mem_used=%s\n' "$(free -m 2>/dev/null | awk '/Mem:/ {printf "%s/%sMB", $3, $2}' || echo unknown)"
    printf 'ssh=%s\n' "$(ng_service_state sshd)"
  } > "${state_file}"

  printf '%s\n' "${state_file}"
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

  if timeout "${NG_PROBE_TIMEOUT}" bash -c "cat < /dev/null > /dev/tcp/${peer_host}/22" >/dev/null 2>&1; then
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

ng_show_local_status() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Local Health Snapshot"
    printf 'Host     : %s\n' "${NG_HOSTNAME}"
    printf 'Uptime   : %s\n' "$(uptime -p 2>/dev/null || uptime)"
    printf 'Load     : %s\n' "$(ng_system_load)"
    printf 'Memory   :\n'
    ng_memory_summary
    printf '\nDisk     :\n'
    ng_disk_summary
    printf '\nPorts    :\n'
  else
    ng_print_header "本机健康快照"
    printf '主机     : %s\n' "${NG_HOSTNAME}"
    printf '运行时长 : %s\n' "$(uptime -p 2>/dev/null || uptime)"
    printf '负载     : %s\n' "$(ng_system_load)"
    printf '内存     :\n'
    ng_memory_summary
    printf '\n磁盘     :\n'
    ng_disk_summary
    printf '\n端口     :\n'
  fi

  ss -lntp 2>/dev/null | sed -n '1,20p' || true
}

ng_local_health() {
  local state_file
  state_file="$(ng_collect_local_probe)"
  
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
  
  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'State saved to: %s\n' "${state_file}"
  else
    printf '状态已保存至: %s\n' "${state_file}"
  fi
}

ng_probe_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛰 Node Management" "Peer reachability and local health inspection"
      ng_print_option "1" "📡" "Probe all peers" "Check ICMP, SSH port and latency for configured peers"
      ng_print_option "2" "🩺" "Local health status" "Collect and display local system status"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛰 节点管理" "节点连通性检查与本机健康状态采集"
      ng_print_option "1" "📡" "探测所有节点" "检查已配置节点的 ICMP、SSH 端口和延迟"
      ng_print_option "2" "🩺" "本机健康状态" "采集并展示本机系统状态"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_probe_all_peers ;;
      2) ng_local_health ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac
  done
}
