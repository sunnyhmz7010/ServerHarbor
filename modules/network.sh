#!/usr/bin/env bash

set -euo pipefail

ng_ping_test() {
  local host="$1"
  local count="${2:-4}"
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Ping Test: ${host}"
    ping -c "${count}" "${host}"
  else
    ng_print_header "Ping 测试: ${host}"
    ping -c "${count}" "${host}"
  fi
}

ng_traceroute_test() {
  local host="$1"
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Traceroute: ${host}"
    if command -v traceroute >/dev/null 2>&1; then
      traceroute "${host}"
    elif command -v tracepath >/dev/null 2>&1; then
      tracepath "${host}"
    else
      printf 'Neither traceroute nor tracepath is available.\n'
      printf 'Install with: apt install traceroute\n'
    fi
  else
    ng_print_header "路由追踪: ${host}"
    if command -v traceroute >/dev/null 2>&1; then
      traceroute "${host}"
    elif command -v tracepath >/dev/null 2>&1; then
      tracepath "${host}"
    else
      printf 'traceroute 和 tracepath 均不可用。\n'
      printf '安装命令: apt install traceroute\n'
    fi
  fi
}

ng_dns_lookup() {
  local domain="$1"
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "DNS Lookup: ${domain}"
    printf 'A Records:\n'
    nslookup -type=A "${domain}" 2>/dev/null || dig A "${domain}" +short 2>/dev/null || printf 'DNS lookup failed\n'
    printf '\nAAAA Records:\n'
    nslookup -type=AAAA "${domain}" 2>/dev/null || dig AAAA "${domain}" +short 2>/dev/null || printf 'No AAAA records\n'
    printf '\nMX Records:\n'
    nslookup -type=MX "${domain}" 2>/dev/null || dig MX "${domain}" +short 2>/dev/null || printf 'No MX records\n'
    printf '\nNS Records:\n'
    nslookup -type=NS "${domain}" 2>/dev/null || dig NS "${domain}" +short 2>/dev/null || printf 'No NS records\n'
  else
    ng_print_header "DNS 查询: ${domain}"
    printf 'A 记录:\n'
    nslookup -type=A "${domain}" 2>/dev/null || dig A "${domain}" +short 2>/dev/null || printf 'DNS 查询失败\n'
    printf '\nAAAA 记录:\n'
    nslookup -type=AAAA "${domain}" 2>/dev/null || dig AAAA "${domain}" +short 2>/dev/null || printf '无 AAAA 记录\n'
    printf '\nMX 记录:\n'
    nslookup -type=MX "${domain}" 2>/dev/null || dig MX "${domain}" +short 2>/dev/null || printf '无 MX 记录\n'
    printf '\nNS 记录:\n'
    nslookup -type=NS "${domain}" 2>/dev/null || dig NS "${domain}" +short 2>/dev/null || printf '无 NS 记录\n'
  fi
}

ng_port_scan() {
  local host="$1"
  local start_port="${2:-1}"
  local end_port="${3:-1024}"
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Port Scan: ${host} (${start_port}-${end_port})"
    printf 'Scanning ports %d to %d...\n' "${start_port}" "${end_port}"
  else
    ng_print_header "端口扫描: ${host} (${start_port}-${end_port})"
    printf '扫描端口 %d 到 %d...\n' "${start_port}" "${end_port}"
  fi
  
  if command -v nmap >/dev/null 2>&1; then
    nmap -p "${start_port}-${end_port}" "${host}"
  else
    local port
    for ((port=start_port; port<=end_port; port++)); do
      if timeout 1 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1; then
        printf 'Port %d: open\n' "${port}"
      fi
    done
  fi
}

ng_bandwidth_test() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Bandwidth Test"
    if command -v speedtest-cli >/dev/null 2>&1; then
      speedtest-cli
    elif command -v speedtest >/dev/null 2>&1; then
      speedtest
    else
      printf 'speedtest-cli is not installed.\n'
      printf 'Install with: pip install speedtest-cli\n'
      printf 'Or use: apt install speedtest-cli\n'
    fi
  else
    ng_print_header "带宽测试"
    if command -v speedtest-cli >/dev/null 2>&1; then
      speedtest-cli
    elif command -v speedtest >/dev/null 2>&1; then
      speedtest
    else
      printf 'speedtest-cli 未安装。\n'
      printf '安装命令: pip install speedtest-cli\n'
      printf '或使用: apt install speedtest-cli\n'
    fi
  fi
}

ng_network_interfaces() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Network Interfaces"
    ip addr show 2>/dev/null || ifconfig 2>/dev/null || printf 'No network interface tool available\n'
    printf '\nRouting Table:\n'
    ip route show 2>/dev/null || route -n 2>/dev/null || printf 'No routing tool available\n'
  else
    ng_print_header "网络接口"
    ip addr show 2>/dev/null || ifconfig 2>/dev/null || printf '无网络接口工具可用\n'
    printf '\n路由表:\n'
    ip route show 2>/dev/null || route -n 2>/dev/null || printf '无路由工具可用\n'
  fi
}

ng_network_connections() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Active Network Connections"
    printf 'Listening Ports:\n'
    ss -lntp 2>/dev/null || netstat -tlnp 2>/dev/null || printf 'No socket tool available\n'
    printf '\nEstablished Connections:\n'
    ss -tnp state established 2>/dev/null || netstat -tnp 2>/dev/null | grep ESTABLISHED || printf 'No established connections\n'
  else
    ng_print_header "活动网络连接"
    printf '监听端口:\n'
    ss -lntp 2>/dev/null || netstat -tlnp 2>/dev/null || printf '无套接字工具可用\n'
    printf '\n已建立连接:\n'
    ss -tnp state established 2>/dev/null || netstat -tnp 2>/dev/null | grep ESTABLISHED || printf '无已建立连接\n'
  fi
}

ng_network_report() {
  local content
  
  if [[ "${NG_LANG}" == "en" ]]; then
    content="$(
      ng_report_title 'ServerHarbor Network Report'
      ng_report_section 'Summary'
      ng_report_kv 'Generated At' "$(ng_timestamp)"
      ng_report_kv 'Host' "${NG_HOSTNAME}"
      ng_report_section 'Network Interfaces'
      ip addr show 2>/dev/null || ifconfig 2>/dev/null || printf 'No network interface tool available\n'
      ng_report_section 'Routing Table'
      ip route show 2>/dev/null || route -n 2>/dev/null || printf 'No routing tool available\n'
      ng_report_section 'Listening Ports'
      ss -lntp 2>/dev/null || netstat -tlnp 2>/dev/null || printf 'No socket tool available\n'
      ng_report_section 'DNS Configuration'
      cat /etc/resolv.conf 2>/dev/null || printf 'No resolv.conf found\n'
    )"
  else
    content="$(
      ng_report_title 'ServerHarbor 网络报告'
      ng_report_section '摘要'
      ng_report_kv '生成时间' "$(ng_timestamp)"
      ng_report_kv '主机' "${NG_HOSTNAME}"
      ng_report_section '网络接口'
      ip addr show 2>/dev/null || ifconfig 2>/dev/null || printf '无网络接口工具可用\n'
      ng_report_section '路由表'
      ip route show 2>/dev/null || route -n 2>/dev/null || printf '无路由工具可用\n'
      ng_report_section '监听端口'
      ss -lntp 2>/dev/null || netstat -tlnp 2>/dev/null || printf '无套接字工具可用\n'
      ng_report_section 'DNS 配置'
      cat /etc/resolv.conf 2>/dev/null || printf '未找到 resolv.conf\n'
    )"
  fi
  
  ng_write_report "network" "${content}" >/dev/null
  printf '%s\n' "${content}"
}

ng_network_diagnostics() {
  local host="$1"
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Network Diagnostics: ${host}"
    printf '1. Ping Test:\n'
    ping -c 3 "${host}" 2>/dev/null || printf 'Ping failed\n'
    printf '\n2. DNS Resolution:\n'
    nslookup "${host}" 2>/dev/null || dig "${host}" +short 2>/dev/null || printf 'DNS resolution failed\n'
    printf '\n3. Port 80 (HTTP):\n'
    if timeout 2 bash -c "cat < /dev/null > /dev/tcp/${host}/80" >/dev/null 2>&1; then
      printf 'Port 80: open\n'
    else
      printf 'Port 80: closed or filtered\n'
    fi
    printf '\n4. Port 443 (HTTPS):\n'
    if timeout 2 bash -c "cat < /dev/null > /dev/tcp/${host}/443" >/dev/null 2>&1; then
      printf 'Port 443: open\n'
    else
      printf 'Port 443: closed or filtered\n'
    fi
  else
    ng_print_header "网络诊断: ${host}"
    printf '1. Ping 测试:\n'
    ping -c 3 "${host}" 2>/dev/null || printf 'Ping 失败\n'
    printf '\n2. DNS 解析:\n'
    nslookup "${host}" 2>/dev/null || dig "${host}" +short 2>/dev/null || printf 'DNS 解析失败\n'
    printf '\n3. 端口 80 (HTTP):\n'
    if timeout 2 bash -c "cat < /dev/null > /dev/tcp/${host}/80" >/dev/null 2>&1; then
      printf '端口 80: 开放\n'
    else
      printf '端口 80: 关闭或被过滤\n'
    fi
    printf '\n4. 端口 443 (HTTPS):\n'
    if timeout 2 bash -c "cat < /dev/null > /dev/tcp/${host}/443" >/dev/null 2>&1; then
      printf '端口 443: 开放\n'
    else
      printf '端口 443: 关闭或被过滤\n'
    fi
  fi
}

ng_network_menu() {
  local choice
  
  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🌐 Network Tools" "Network diagnostics, testing and monitoring"
      ng_print_option "1" "📡" "Ping test" "Test host connectivity"
      ng_print_option "2" "🗺" "Traceroute" "Trace network path to host"
      ng_print_option "3" "🔍" "DNS lookup" "Query DNS records for domain"
      ng_print_option "4" "🚪" "Port scan" "Scan open ports on host"
      ng_print_option "5" "📶" "Bandwidth test" "Test internet connection speed"
      ng_print_option "6" "🔌" "Network interfaces" "Show network interface details"
      ng_print_option "7" "🔗" "Active connections" "Show active network connections"
      ng_print_option "8" "🛠" "Network diagnostics" "Comprehensive network test"
      ng_print_option "9" "📄" "Generate network report" "Create detailed network report"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🌐 网络工具" "网络诊断、测试与监控"
      ng_print_option "1" "📡" "Ping 测试" "测试主机连通性"
      ng_print_option "2" "🗺" "路由追踪" "追踪到主机的网络路径"
      ng_print_option "3" "🔍" "DNS 查询" "查询域名的 DNS 记录"
      ng_print_option "4" "🚪" "端口扫描" "扫描主机开放端口"
      ng_print_option "5" "📶" "带宽测试" "测试互联网连接速度"
      ng_print_option "6" "🔌" "网络接口" "显示网络接口详细信息"
      ng_print_option "7" "🔗" "活动连接" "显示活动网络连接"
      ng_print_option "8" "🛠" "网络诊断" "综合网络测试"
      ng_print_option "9" "📄" "生成网络报告" "创建详细网络报告"
      ng_print_option "0" "↩" "返回"
    fi
    
    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130
    
    case "${choice}" in
      1)
        local host
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter host to ping: '
        else
          printf '请输入要 ping 的主机: '
        fi
        ng_read_line host || return 130
        ng_ping_test "${host}"
        ;;
      2)
        local host
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter host for traceroute: '
        else
          printf '请输入要追踪路由的主机: '
        fi
        ng_read_line host || return 130
        ng_traceroute_test "${host}"
        ;;
      3)
        local domain
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter domain for DNS lookup: '
        else
          printf '请输入要查询 DNS 的域名: '
        fi
        ng_read_line domain || return 130
        ng_dns_lookup "${domain}"
        ;;
      4)
        local host start_port end_port
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter host to scan: '
        else
          printf '请输入要扫描的主机: '
        fi
        ng_read_line host || return 130
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Start port (default 1): '
        else
          printf '起始端口（默认 1）: '
        fi
        ng_read_line start_port || return 130
        start_port="${start_port:-1}"
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'End port (default 1024): '
        else
          printf '结束端口（默认 1024）: '
        fi
        ng_read_line end_port || return 130
        end_port="${end_port:-1024}"
        ng_port_scan "${host}" "${start_port}" "${end_port}"
        ;;
      5) ng_bandwidth_test ;;
      6) ng_network_interfaces ;;
      7) ng_network_connections ;;
      8)
        local host
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter host for diagnostics: '
        else
          printf '请输入要诊断的主机: '
        fi
        ng_read_line host || return 130
        ng_network_diagnostics "${host}"
        ;;
      9) ng_network_report ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac
    
    ng_press_enter || return 130
  done
}