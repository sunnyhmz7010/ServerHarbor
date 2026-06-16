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
    printf '---------------------------------------------------------------------\n'
    while IFS=',' read -r peer_alias peer_host; do
      [[ -n "${peer_alias}" && -n "${peer_host}" ]] || continue
      ng_probe_single_peer "${peer_host}" "${peer_alias}"
    done < <(ng_read_peers)
  } | tee "${output_file}"

  report="$(
    printf 'ServerHarbor Probe Report\n'
    printf 'Generated at: %s\n' "$(ng_timestamp)"
    printf 'Host        : %s\n\n' "${NG_HOSTNAME}"
    cat "${output_file}"
    printf '\n[Local Snapshot]\n'
    cat "$(ng_collect_local_probe)"
  )"

  ng_write_report "probe" "${report}" >/dev/null
  printf '%s\n' "${report}"
}

ng_show_local_status() {
  ng_print_header "Local Health Snapshot"
  printf 'Host     : %s\n' "${NG_HOSTNAME}"
  printf 'Uptime   : %s\n' "$(uptime -p 2>/dev/null || uptime)"
  printf 'Load     : %s\n' "$(ng_system_load)"
  printf 'Memory   :\n'
  ng_memory_summary
  printf '\nDisk     :\n'
  ng_disk_summary
  printf '\nPorts    :\n'
  ss -lntp 2>/dev/null | sed -n '1,20p' || true
}

ng_probe_menu() {
  local choice

  while true; do
    ng_print_header "Peer Probe"
    cat <<'EOF'
1. Probe all peers
2. Collect local status snapshot
3. Show local health
0. Back
EOF
    printf 'Select: '
    read -r choice

    case "${choice}" in
      1) ng_probe_all_peers ;;
      2) cat "$(ng_collect_local_probe)" ;;
      3) ng_show_local_status ;;
      0) break ;;
      *) printf 'Invalid option.\n' ;;
    esac
  done
}
