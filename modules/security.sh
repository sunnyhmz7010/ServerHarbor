#!/usr/bin/env bash

set -euo pipefail

ng_scan_auth_failures() {
  local auth_log=""
  local summary=""

  if [[ -f /var/log/auth.log ]]; then
    auth_log="/var/log/auth.log"
  elif [[ -f /var/log/secure ]]; then
    auth_log="/var/log/secure"
  fi

  if [[ -z "${auth_log}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No auth log found.\n'
    else
      printf '未找到认证日志文件。\n'
    fi
    return 0
  fi

  summary="$(
    grep -Ei 'Failed password|authentication failure' "${auth_log}" 2>/dev/null \
      | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
      | sort | uniq -c | sort -nr | head || true
  )"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section 'Failed Login Sources'
    ng_report_kv 'Auth Log' "${auth_log}"
    ng_report_note 'Top source IPs by failed password events:'
  else
    ng_report_section '失败登录来源'
    ng_report_kv '日志文件' "${auth_log}"
    ng_report_note '以下为失败密码登录事件最多的来源 IP：'
  fi

  if [[ -z "${summary}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_report_note 'No failed login entries found.'
    else
      ng_report_note '未发现失败登录记录。'
    fi
    return 0
  fi

  printf '%s\n' "${summary}"
}

ng_scan_web_attacks() {
  local access_log="/var/log/nginx/access.log"
  local summary=""

  [[ -f "${access_log}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_report_section 'Suspicious Web Requests'
      ng_report_note 'No nginx access log found.'
    else
      ng_report_section '可疑 Web 请求'
      ng_report_note '未找到 nginx 访问日志。'
    fi
    return 0
  }

  summary="$(
    grep -Ei 'wp-admin|phpmyadmin|\.env|/admin|/login|select.+from|union.+select' "${access_log}" \
      | awk '{print $1}' | sort | uniq -c | sort -nr | head || true
  )"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section 'Suspicious Web Requests'
    ng_report_kv 'Access Log' "${access_log}"
    ng_report_note 'Top source IPs matching common suspicious request patterns:'
  else
    ng_report_section '可疑 Web 请求'
    ng_report_kv '访问日志' "${access_log}"
    ng_report_note '以下为命中常见可疑请求特征最多的来源 IP：'
  fi

  if [[ -z "${summary}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_report_note 'No suspicious request patterns found.'
    else
      ng_report_note '未发现可疑请求特征。'
    fi
    return 0
  fi

  printf '%s\n' "${summary}"
}

ng_firewall_summary() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section 'Firewall Summary'
    ng_report_note 'Detected firewall backend and current active rules:'
  else
    ng_report_section '防火墙状态'
    ng_report_note '以下为检测到的防火墙后端及当前生效规则：'
  fi

  if command -v ufw >/dev/null 2>&1; then
    ng_report_kv 'Backend' 'ufw'
    ufw status verbose || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    ng_report_kv 'Backend' 'firewalld'
    firewall-cmd --list-all || true
  elif command -v iptables >/dev/null 2>&1; then
    ng_report_kv 'Backend' 'iptables'
    iptables -L -n --line-numbers || true
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_report_note 'No firewall tool found.'
    else
      ng_report_note '未找到防火墙工具。'
    fi
  fi
}

ng_simple_firewall_hardening() {
  ng_require_root || return 1

  if command -v ufw >/dev/null 2>&1; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw --force enable
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --reload
  else
    ng_log "WARN" "No supported firewall manager found."
  fi
}

ng_integrity_create_baseline() {
  local baseline_file="${NG_INTEGRITY_DB}"

  [[ -f "${NG_WATCH_FILE}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Watch file is missing: %s\n' "${NG_WATCH_FILE}"
    else
      printf '监控路径配置文件不存在：%s\n' "${NG_WATCH_FILE}"
    fi
    return 1
  }

  : > "${baseline_file}"
  while IFS= read -r watch_path; do
    [[ -n "${watch_path}" && "${watch_path}" != \#* ]] || continue
    if [[ -e "${watch_path}" ]]; then
      find "${watch_path}" -type f -exec sha256sum {} \; >> "${baseline_file}"
    fi
  done < "${NG_WATCH_FILE}"

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Integrity baseline written to %s\n' "${baseline_file}"
  else
    printf '完整性基线已写入：%s\n' "${baseline_file}"
  fi
}

ng_integrity_verify() {
  if [[ ! -f "${NG_INTEGRITY_DB}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No integrity baseline found. Create one first.\n'
    else
      printf '未找到完整性基线，请先生成。\n'
    fi
    return 1
  fi

  (cd / && sha256sum -c "${NG_INTEGRITY_DB}") 2>/dev/null || true
}

ng_security_report() {
  local content

  if [[ "${NG_LANG}" == "en" ]]; then
    content="$(
      ng_report_title 'ServerHarbor Security Report'
      ng_report_section 'Summary'
      ng_report_kv 'Generated At' "$(ng_timestamp)"
      ng_report_kv 'Host' "${NG_HOSTNAME}"
      ng_report_section 'Failed Login Sources'
      ng_scan_auth_failures
      ng_report_section 'Suspicious Web Requests'
      ng_scan_web_attacks
      ng_report_section 'Listening Ports'
      ss -lntp 2>/dev/null | sed -n '1,25p' || true
      ng_report_section 'Firewall'
      ng_firewall_summary
    )"
  else
    content="$(
      ng_report_title 'ServerHarbor 安全巡检报告'
      ng_report_section '摘要'
      ng_report_kv '生成时间' "$(ng_timestamp)"
      ng_report_kv '主机' "${NG_HOSTNAME}"
      ng_report_section '失败登录来源'
      ng_scan_auth_failures
      ng_report_section '可疑 Web 请求'
      ng_scan_web_attacks
      ng_report_section '监听端口'
      ss -lntp 2>/dev/null | sed -n '1,25p' || true
      ng_report_section '防火墙'
      ng_firewall_summary
    )"
  fi

  ng_write_report "security" "${content}" >/dev/null
  printf '%s\n' "${content}"
}

ng_rootkit_check() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Rootkit Detection"
    printf 'Checking for common rootkits and suspicious files...\n'
  else
    ng_print_header "Rootkit 检测"
    printf '检查常见 rootkit 和可疑文件...\n'
  fi
  
  local suspicious_files=(
    "/usr/bin/... "
    "/usr/bin/.xx"
    "/usr/bin/.sniffer"
    "/usr/bin/.squid"
    "/usr/lib/.x"
    "/usr/lib/.sniffer"
    "/dev/.udev"
    "/dev/.udevdb"
    "/dev/.udev.tdb"
    "/etc/cron.d/core.cron"
    "/etc/cron.d/.kork"
    "/etc/cron.d/.0"
    "/tmp/.X11-unix"
    "/tmp/.ICE-unix"
    "/tmp/.font-unix"
    "/tmp/.XIM-unix"
  )
  
  local found=0
  for file in "${suspicious_files[@]}"; do
    if [[ -e "${file}" ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '⚠️  Suspicious file found: %s\n' "${file}"
      else
        printf '⚠️  发现可疑文件: %s\n' "${file}"
      fi
      found=1
    fi
  done
  
  if [[ "${found}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "INFO" "No common rootkit files detected"
    else
      ng_log "INFO" "未检测到常见 rootkit 文件"
    fi
  fi
  
  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nChecking for suspicious processes...\n'
    ps aux | awk '{print $11}' | grep -E '^\.' | head -10 || true
    printf '\nChecking for hidden files in /tmp...\n'
    find /tmp -name ".*" -type f 2>/dev/null | head -10 || true
  else
    printf '\n检查可疑进程...\n'
    ps aux | awk '{print $11}' | grep -E '^\.' | head -10 || true
    printf '\n检查 /tmp 目录中的隐藏文件...\n'
    find /tmp -name ".*" -type f 2>/dev/null | head -10 || true
  fi
}

ng_port_security_scan() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Port Security Scan"
    printf 'Scanning for open ports and potential security risks...\n'
  else
    ng_print_header "端口安全扫描"
    printf '扫描开放端口和潜在安全风险...\n'
  fi
  
  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Listening ports:\n'
    ss -lntp 2>/dev/null | awk 'NR>1 {print $4, $6}' | sort -u
    printf '\nPotential high-risk ports:\n'
    ss -lntp 2>/dev/null | grep -E ':(23|25|53|80|110|143|443|993|995|3306|3389|5432|5900|6379|8080|8443|27017)\b' || printf 'No high-risk ports detected\n'
  else
    printf '监听端口:\n'
    ss -lntp 2>/dev/null | awk 'NR>1 {print $4, $6}' | sort -u
    printf '\n潜在高风险端口:\n'
    ss -lntp 2>/dev/null | grep -E ':(23|25|53|80|110|143|443|993|995|3306|3389|5432|5900|6379|8080|8443|27017)\b' || printf '未检测到高风险端口\n'
  fi
}

ng_security_score() {
  local score=100
  local issues=()
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Security Score Calculation"
    printf 'Calculating security score...\n'
  else
    ng_print_header "安全评分计算"
    printf '正在计算安全评分...\n'
  fi
  
  if [[ "${EUID}" -eq 0 ]]; then
    score=$((score - 10))
    issues+=("Running as root (-10)")
  fi
  
  if ! grep -q "PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
    score=$((score - 15))
    issues+=("SSH password authentication enabled (-15)")
  fi
  
  if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
    score=$((score - 20))
    issues+=("Root login permitted (-20)")
  fi
  
  if ! command -v ufw >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1 && ! command -v iptables >/dev/null 2>&1; then
    score=$((score - 25))
    issues+=("No firewall detected (-25)")
  fi
  
  if [[ -f /var/log/auth.log ]]; then
    local failed_count
    failed_count=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo 0)
    if [[ "${failed_count}" -gt 100 ]]; then
      score=$((score - 10))
      issues+=("High number of failed login attempts: ${failed_count} (-10)")
    fi
  fi
  
  if [[ "${score}" -lt 0 ]]; then
    score=0
  fi
  
  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nSecurity Score: %d/100\n' "${score}"
    if [[ "${#issues[@]}" -gt 0 ]]; then
      printf '\nIssues found:\n'
      for issue in "${issues[@]}"; do
        printf '  • %s\n' "${issue}"
      done
    else
      printf 'No major security issues found.\n'
    fi
  else
    printf '\n安全评分: %d/100\n' "${score}"
    if [[ "${#issues[@]}" -gt 0 ]]; then
      printf '\n发现的问题:\n'
      for issue in "${issues[@]}"; do
        printf '  • %s\n' "${issue}"
      done
    else
      printf '未发现重大安全问题。\n'
    fi
  fi
}

ng_security_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛡 Security Guard" "Auth logs, web attacks, firewall, integrity and rootkit detection"
      ng_print_option "1" "📄" "Run security report" "Aggregate auth failures, web probes, ports and firewall state"
      ng_print_option "2" "🔍" "Show failed login statistics" "Count recent failed login source IPs"
      ng_print_option "3" "🌐" "Show suspicious web requests" "Inspect nginx access log for common attack patterns"
      ng_print_option "4" "🔥" "Show firewall summary" "Display ufw, firewalld or iptables state"
      ng_print_option "5" "🧬" "Create integrity baseline" "Hash all files under configured watch paths"
      ng_print_option "6" "✅" "Verify integrity baseline" "Check current files against stored hashes"
      ng_print_option "7" "🔒" "Apply simple firewall hardening" "Allow SSH and enable default deny for incoming traffic"
      ng_print_option "8" "🦠" "Rootkit detection" "Check for common rootkits and suspicious files"
      ng_print_option "9" "🚪" "Port security scan" "Scan for open ports and potential risks"
      ng_print_option "10" "📊" "Security score" "Calculate system security score"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛡 安全卫士" "认证日志、Web 攻击、防火墙、完整性与 Rootkit 检测"
      ng_print_option "1" "📄" "生成安全报告" "汇总认证失败、Web 探测、端口与防火墙状态"
      ng_print_option "2" "🔍" "查看失败登录统计" "统计近期失败登录来源 IP"
      ng_print_option "3" "🌐" "查看可疑 Web 请求" "检查 nginx 访问日志中的常见攻击特征"
      ng_print_option "4" "🔥" "查看防火墙状态" "显示 ufw、firewalld 或 iptables 状态"
      ng_print_option "5" "🧬" "生成完整性基线" "对监控路径下文件生成哈希清单"
      ng_print_option "6" "✅" "校验完整性基线" "按已有哈希清单检查当前文件"
      ng_print_option "7" "🔒" "应用简单防火墙加固" "放行 SSH，并默认拒绝新入站连接"
      ng_print_option "8" "🦠" "Rootkit 检测" "检查常见 rootkit 和可疑文件"
      ng_print_option "9" "🚪" "端口安全扫描" "扫描开放端口和潜在风险"
      ng_print_option "10" "📊" "安全评分" "计算系统安全评分"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_security_report ;;
      2) ng_scan_auth_failures ;;
      3) ng_scan_web_attacks ;;
      4) ng_firewall_summary ;;
      5) ng_integrity_create_baseline ;;
      6) ng_integrity_verify ;;
      7)
        if [[ "${NG_LANG}" == "en" ]]; then
          if ng_prompt_yes_no "Apply simple firewall hardening now?"; then
            ng_simple_firewall_hardening
          fi
        else
          if ng_prompt_yes_no "是否立即应用简单防火墙加固？"; then
            ng_simple_firewall_hardening
          fi
        fi
        ;;
      8) ng_rootkit_check ;;
      9) ng_port_security_scan ;;
      10) ng_security_score ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac
  done
}
