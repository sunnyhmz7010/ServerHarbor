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

  if ping -c 1 -W "${NG_PROBE_TIMEOUT}" "${peer_host}" >/dev/null 2>&1; then
    ping_result="up"
    latency="$(ping -c 1 -W "${NG_PROBE_TIMEOUT}" "${peer_host}" 2>/dev/null | awk -F'time=' 'END {print $2}' | awk '{print $1}' || echo n/a)"
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
  local report

  {
    printf 'Peer Alias       Peer Host                ICMP     SSH Port   Latency\n'
    printf '%s\n' '---------------------------------------------------------------------'
    while IFS=',' read -r peer_alias peer_host; do
      [[ -n "${peer_alias}" && -n "${peer_host}" ]] || continue
      ng_probe_single_peer "${peer_host}" "${peer_alias}"
    done < <(ng_read_peers)
  } | tee "${output_file}"

  if [[ "${NG_LANG}" == "en" ]]; then
    report="$(
      ng_report_title 'ServerHarbor Probe Report'
      ng_report_section 'Summary'
      ng_report_kv 'Generated At' "$(ng_timestamp)"
      ng_report_kv 'Host' "${NG_HOSTNAME}"
      ng_report_section 'Peer Matrix'
      cat "${output_file}"
      ng_report_section 'Local Snapshot'
      cat "$(ng_collect_local_probe)"
    )"
  else
    report="$(
      ng_report_title 'ServerHarbor 节点探测报告'
      ng_report_section '摘要'
      ng_report_kv '生成时间' "$(ng_timestamp)"
      ng_report_kv '主机' "${NG_HOSTNAME}"
      ng_report_section '节点矩阵'
      cat "${output_file}"
      ng_report_section '本机快照'
      cat "$(ng_collect_local_probe)"
    )"
  fi

  ng_write_report "probe" "${report}" >/dev/null
  printf '%s\n' "${report}"
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

ng_probe_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛰 Peer Probe" "Peer reachability and local health inspection"
      ng_print_option "1" "📡" "Probe all peers" "Check ICMP, SSH port and latency for configured peers"
      ng_print_option "2" "🧾" "Collect local status snapshot" "Write the current local state into the state directory"
      ng_print_option "3" "🩺" "Show local health" "Inspect uptime, load, memory, disk and listening ports"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛰 节点探测" "检查节点连通性，并采集本机健康状态"
      ng_print_option "1" "📡" "探测所有节点" "检查已配置节点的 ICMP、SSH 端口和延迟"
      ng_print_option "2" "🧾" "采集本机状态快照" "将当前本机状态写入 state 目录"
      ng_print_option "3" "🩺" "查看本机健康状态" "检查运行时长、负载、内存、磁盘与监听端口"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_probe_all_peers ;;
      2) cat "$(ng_collect_local_probe)" ;;
      3) ng_show_local_status ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac
  done
}
