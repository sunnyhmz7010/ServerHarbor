#!/usr/bin/env bash

set -euo pipefail

ng_cpu_usage() {
  local cpu_usage
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
  if [[ -z "${cpu_usage}" ]]; then
    cpu_usage=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.1f", usage}')
  fi
  printf '%s' "${cpu_usage:-0}"
}

ng_memory_usage() {
  free -m | awk '/Mem:/ {printf "%.1f", $3/$2*100}'
}

ng_disk_usage() {
  df -h / | awk 'NR==2 {print $5}' | cut -d'%' -f1
}

ng_system_load() {
  uptime | awk -F'load average: ' '{print $2}' | tr -d '\r'
}

ng_process_count() {
  ps aux | wc -l | tr -d ' '
}

ng_network_connections() {
  ss -s | awk '/^TCP:/ {print $2}'
}

ng_monitor_single() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "System Monitor Snapshot"
    printf 'CPU Usage      : %s%%\n' "$(ng_cpu_usage)"
    printf 'Memory Usage   : %s%%\n' "$(ng_memory_usage)"
    printf 'Disk Usage     : %s%%\n' "$(ng_disk_usage)"
    printf 'System Load    : %s\n' "$(ng_system_load)"
    printf 'Process Count  : %s\n' "$(ng_process_count)"
    printf 'TCP Connections: %s\n' "$(ng_network_connections)"
    printf '\nTop 5 CPU Processes:\n'
    ps aux --sort=-%cpu | head -6
    printf '\nTop 5 Memory Processes:\n'
    ps aux --sort=-%mem | head -6
  else
    ng_print_header "系统监控快照"
    printf 'CPU 使用率     : %s%%\n' "$(ng_cpu_usage)"
    printf '内存使用率     : %s%%\n' "$(ng_memory_usage)"
    printf '磁盘使用率     : %s%%\n' "$(ng_disk_usage)"
    printf '系统负载       : %s\n' "$(ng_system_load)"
    printf '进程数量       : %s\n' "$(ng_process_count)"
    printf 'TCP 连接数     : %s\n' "$(ng_network_connections)"
    printf '\nCPU 占用前 5 进程:\n'
    ps aux --sort=-%cpu | head -6
    printf '\n内存占用前 5 进程:\n'
    ps aux --sort=-%mem | head -6
  fi
}

ng_monitor_realtime() {
  local interval="${1:-2}"
  local count=0
  
  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Starting real-time monitor (refresh every %ds, Ctrl+C to stop)\n' "${interval}"
  else
    printf '启动实时监控（每 %d 秒刷新，按 Ctrl+C 停止）\n' "${interval}"
  fi
  
  while true; do
    clear || true
    count=$((count + 1))
    
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "📊 Real-time System Monitor" "Refresh #${count} - $(date '+%H:%M:%S')"
      printf '  %s %-15s %s\n' "🖥" "CPU Usage" "$(ng_cpu_usage)%"
      printf '  %s %-15s %s\n' "🧠" "Memory Usage" "$(ng_memory_usage)%"
      printf '  %s %-15s %s\n' "💾" "Disk Usage" "$(ng_disk_usage)%"
      printf '  %s %-15s %s\n' "📈" "System Load" "$(ng_system_load)"
      printf '  %s %-15s %s\n' "⚙️" "Processes" "$(ng_process_count)"
      printf '  %s %-15s %s\n' "🌐" "TCP Conn" "$(ng_network_connections)"
      printf '\n%s\n' "$(ng_color "${NG_C_DIM}" "Press Ctrl+C to stop monitoring")"
    else
      ng_print_title_box "📊 实时系统监控" "刷新 #${count} - $(date '+%H:%M:%S')"
      printf '  %s %-15s %s\n' "🖥" "CPU 使用率" "$(ng_cpu_usage)%"
      printf '  %s %-15s %s\n' "🧠" "内存使用率" "$(ng_memory_usage)%"
      printf '  %s %-15s %s\n' "💾" "磁盘使用率" "$(ng_disk_usage)%"
      printf '  %s %-15s %s\n' "📈" "系统负载" "$(ng_system_load)"
      printf '  %s %-15s %s\n' "⚙️" "进程数量" "$(ng_process_count)"
      printf '  %s %-15s %s\n' "🌐" "TCP 连接" "$(ng_network_connections)"
      printf '\n%s\n' "$(ng_color "${NG_C_DIM}" "按 Ctrl+C 停止监控")"
    fi
    
    sleep "${interval}"
  done
}

ng_monitor_report() {
  local content
  
  if [[ "${NG_LANG}" == "en" ]]; then
    content="$(
      ng_report_title 'ServerHarbor Monitor Report'
      ng_report_section 'Summary'
      ng_report_kv 'Generated At' "$(ng_timestamp)"
      ng_report_kv 'Host' "${NG_HOSTNAME}"
      ng_report_section 'System Resources'
      ng_report_kv 'CPU Usage' "$(ng_cpu_usage)%"
      ng_report_kv 'Memory Usage' "$(ng_memory_usage)%"
      ng_report_kv 'Disk Usage' "$(ng_disk_usage)%"
      ng_report_kv 'System Load' "$(ng_system_load)"
      ng_report_kv 'Process Count' "$(ng_process_count)"
      ng_report_kv 'TCP Connections' "$(ng_network_connections)"
      ng_report_section 'Top CPU Processes'
      ps aux --sort=-%cpu | head -6
      ng_report_section 'Top Memory Processes'
      ps aux --sort=-%mem | head -6
    )"
  else
    content="$(
      ng_report_title 'ServerHarbor 系统监控报告'
      ng_report_section '摘要'
      ng_report_kv '生成时间' "$(ng_timestamp)"
      ng_report_kv '主机' "${NG_HOSTNAME}"
      ng_report_section '系统资源'
      ng_report_kv 'CPU 使用率' "$(ng_cpu_usage)%"
      ng_report_kv '内存使用率' "$(ng_memory_usage)%"
      ng_report_kv '磁盘使用率' "$(ng_disk_usage)%"
      ng_report_kv '系统负载' "$(ng_system_load)"
      ng_report_kv '进程数量' "$(ng_process_count)"
      ng_report_kv 'TCP 连接数' "$(ng_network_connections)"
      ng_report_section 'CPU 占用前 5 进程'
      ps aux --sort=-%cpu | head -6
      ng_report_section '内存占用前 5 进程'
      ps aux --sort=-%mem | head -6
    )"
  fi
  
  ng_write_report "monitor" "${content}" >/dev/null
  printf '%s\n' "${content}"
}

ng_monitor_alert() {
  local cpu_threshold="${1:-80}"
  local mem_threshold="${2:-80}"
  local disk_threshold="${3:-90}"
  local alerts=()
  
  local cpu_usage mem_usage disk_usage
  cpu_usage=$(ng_cpu_usage | cut -d'.' -f1)
  mem_usage=$(ng_memory_usage | cut -d'.' -f1)
  disk_usage=$(ng_disk_usage)
  
  if [[ "${cpu_usage}" -gt "${cpu_threshold}" ]]; then
    alerts+=("CPU usage (${cpu_usage}%) exceeds threshold (${cpu_threshold}%)")
  fi
  
  if [[ "${mem_usage}" -gt "${mem_threshold}" ]]; then
    alerts+=("Memory usage (${mem_usage}%) exceeds threshold (${mem_threshold}%)")
  fi
  
  if [[ "${disk_usage}" -gt "${disk_threshold}" ]]; then
    alerts+=("Disk usage (${disk_usage}%) exceeds threshold (${disk_threshold}%)")
  fi
  
  if [[ "${#alerts[@]}" -gt 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "System Alerts"
      printf '⚠️  System resource alerts detected:\n'
      for alert in "${alerts[@]}"; do
        printf '  • %s\n' "${alert}"
      done
    else
      ng_print_header "系统告警"
      printf '⚠️  检测到系统资源告警:\n'
      for alert in "${alerts[@]}"; do
        printf '  • %s\n' "${alert}"
      done
    fi
    return 1
  fi
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_log "INFO" "System resources within normal thresholds"
  else
    ng_log "INFO" "系统资源在正常阈值内"
  fi
  return 0
}

ng_monitor_menu() {
  local choice
  
  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "📊 System Monitor" "Real-time system resource monitoring and alerts"
      ng_print_option "1" "📸" "Single snapshot" "View current system resource usage"
      ng_print_option "2" "🔄" "Real-time monitor" "Continuous monitoring with refresh"
      ng_print_option "3" "📄" "Generate monitor report" "Create detailed system report"
      ng_print_option "4" "⚠️" "Check system alerts" "Check for resource threshold violations"
      ng_print_option "5" "⚙️" "Configure alert thresholds" "Set CPU, memory, and disk thresholds"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "📊 系统监控" "实时系统资源监控与告警"
      ng_print_option "1" "📸" "单次快照" "查看当前系统资源使用情况"
      ng_print_option "2" "🔄" "实时监控" "持续监控并刷新显示"
      ng_print_option "3" "📄" "生成监控报告" "创建详细的系统报告"
      ng_print_option "4" "⚠️" "检查系统告警" "检查资源阈值违规情况"
      ng_print_option "5" "⚙️" "配置告警阈值" "设置 CPU、内存和磁盘阈值"
      ng_print_option "0" "↩" "返回"
    fi
    
    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130
    
    case "${choice}" in
      1) ng_monitor_single ;;
      2)
        local interval
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Refresh interval (seconds, default 2): '
        else
          printf '刷新间隔（秒，默认 2）: '
        fi
        ng_read_line interval || return 130
        interval="${interval:-2}"
        ng_monitor_realtime "${interval}"
        ;;
      3) ng_monitor_report ;;
      4) ng_monitor_alert ;;
      5)
        local cpu_thresh mem_thresh disk_thresh
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'CPU threshold (%%, default 80): '
        else
          printf 'CPU 阈值（%%，默认 80）: '
        fi
        ng_read_line cpu_thresh || return 130
        cpu_thresh="${cpu_thresh:-80}"
        
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Memory threshold (%%, default 80): '
        else
          printf '内存阈值（%%，默认 80）: '
        fi
        ng_read_line mem_thresh || return 130
        mem_thresh="${mem_thresh:-80}"
        
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Disk threshold (%%, default 90): '
        else
          printf '磁盘阈值（%%，默认 90）: '
        fi
        ng_read_line disk_thresh || return 130
        disk_thresh="${disk_thresh:-90}"
        
        ng_monitor_alert "${cpu_thresh}" "${mem_thresh}" "${disk_thresh}"
        ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac
    
    ng_press_enter || return 130
  done
}