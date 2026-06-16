#!/usr/bin/env bash

set -euo pipefail

ng_scan_auth_failures() {
  local auth_log=""

  if [[ -f /var/log/auth.log ]]; then
    auth_log="/var/log/auth.log"
  elif [[ -f /var/log/secure ]]; then
    auth_log="/var/log/secure"
  fi

  if [[ -z "${auth_log}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No auth log found.\n'; else printf '未找到认证日志文件。\n'; fi
    return 0
  fi

  if [[ "${NG_LANG}" == "en" ]]; then printf '[Top Failed Login IPs]\n'; else printf '[失败登录来源 IP Top]\n'; fi
  grep -Ei 'Failed password|authentication failure' "${auth_log}" 2>/dev/null \
    | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | sort | uniq -c | sort -nr | head
}

ng_scan_web_attacks() {
  local access_log="/var/log/nginx/access.log"

  [[ -f "${access_log}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No nginx access log found.\n'; else printf '未找到 nginx 访问日志。\n'; fi
    return 0
  }

  if [[ "${NG_LANG}" == "en" ]]; then printf '[Suspicious Web Requests]\n'; else printf '[可疑 Web 请求]\n'; fi
  grep -Ei 'wp-admin|phpmyadmin|\.env|/admin|/login|select.+from|union.+select' "${access_log}" \
    | awk '{print $1}' | sort | uniq -c | sort -nr | head
}

ng_firewall_summary() {
  if command -v ufw >/dev/null 2>&1; then
    ufw status verbose || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --list-all || true
  elif command -v iptables >/dev/null 2>&1; then
    iptables -L -n --line-numbers || true
  else
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No firewall tool found.\n'; else printf '未找到防火墙工具。\n'; fi
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
    if [[ "${NG_LANG}" == "en" ]]; then printf 'Watch file is missing: %s\n' "${NG_WATCH_FILE}"; else printf '监控路径配置文件不存在：%s\n' "${NG_WATCH_FILE}"; fi
    return 1
  }

  : > "${baseline_file}"
  while IFS= read -r watch_path; do
    [[ -n "${watch_path}" && "${watch_path}" != \#* ]] || continue
    if [[ -e "${watch_path}" ]]; then
      find "${watch_path}" -type f -exec sha256sum {} \; >> "${baseline_file}"
    fi
  done < "${NG_WATCH_FILE}"

  if [[ "${NG_LANG}" == "en" ]]; then printf 'Integrity baseline written to %s\n' "${baseline_file}"; else printf '完整性基线已写入：%s\n' "${baseline_file}"; fi
}

ng_integrity_verify() {
  if [[ ! -f "${NG_INTEGRITY_DB}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No integrity baseline found. Create one first.\n'; else printf '未找到完整性基线，请先生成。\n'; fi
    return 1
  fi

  (cd / && sha256sum -c "${NG_INTEGRITY_DB}") 2>/dev/null || true
}

ng_security_report() {
  local content

  content="$(
    printf 'ServerHarbor Security Report\n'
    ng_t generated_at "$(ng_timestamp)"
    printf 'Host        : %s\n\n' "${NG_HOSTNAME}"
    ng_scan_auth_failures
    printf '\n'
    ng_scan_web_attacks
    printf '\n[Listening Ports]\n'
    ss -lntp 2>/dev/null | sed -n '1,25p' || true
    printf '\n[Firewall]\n'
    ng_firewall_summary
  )"

  ng_write_report "security" "${content}" >/dev/null
  printf '%s\n' "${content}"
}

ng_security_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "Security Guard"
      cat <<'EOF'
1. Run security report
2. Show failed login statistics
3. Show suspicious web requests
4. Show firewall summary
5. Apply simple firewall hardening
0. Back
EOF
    else
      ng_print_header "安全巡检"
      cat <<'EOF'
1. 生成安全报告
2. 查看失败登录统计
3. 查看可疑 Web 请求
4. 查看防火墙状态
5. 应用简单防火墙加固
0. 返回
EOF
    fi
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_security_report ;;
      2) ng_scan_auth_failures ;;
      3) ng_scan_web_attacks ;;
      4) ng_firewall_summary ;;
      5)
        if [[ "${NG_LANG}" == "en" ]]; then
          if ng_prompt_yes_no "Apply simple firewall hardening now?"; then ng_simple_firewall_hardening; fi
        else
          if ng_prompt_yes_no "是否立即应用简单防火墙加固？"; then ng_simple_firewall_hardening; fi
        fi
        ;;
      0) break ;;
      *) ng_t invalid_option ;;
    esac
  done
}

ng_integrity_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "Integrity Monitor"
      cat <<'EOF'
1. Create integrity baseline
2. Verify integrity baseline
0. Back
EOF
    else
      ng_print_header "完整性监控"
      cat <<'EOF'
1. 生成完整性基线
2. 校验完整性基线
0. 返回
EOF
    fi
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_integrity_create_baseline ;;
      2) ng_integrity_verify ;;
      0) break ;;
      *) ng_t invalid_option ;;
    esac
  done
}
