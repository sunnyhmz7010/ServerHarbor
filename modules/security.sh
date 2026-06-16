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
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No auth log found.\n'
    else
      printf '未找到认证日志文件。\n'
    fi
    return 0
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '[Top Failed Login IPs]\n'
  else
    printf '[失败登录来源 IP Top]\n'
  fi

  grep -Ei 'Failed password|authentication failure' "${auth_log}" 2>/dev/null \
    | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | sort | uniq -c | sort -nr | head
}

ng_scan_web_attacks() {
  local access_log="/var/log/nginx/access.log"

  [[ -f "${access_log}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No nginx access log found.\n'
    else
      printf '未找到 nginx 访问日志。\n'
    fi
    return 0
  }

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '[Suspicious Web Requests]\n'
  else
    printf '[可疑 Web 请求]\n'
  fi

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
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No firewall tool found.\n'
    else
      printf '未找到防火墙工具。\n'
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

ng_security_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛡 Security Guard" "Lightweight inspection and basic hardening"
      ng_print_option "1" "📄" "Run security report" "Aggregate auth failures, web probes, ports and firewall state"
      ng_print_option "2" "🔍" "Show failed login statistics" "Count recent failed login source IPs"
      ng_print_option "3" "🌐" "Show suspicious web requests" "Inspect nginx access log for common attack patterns"
      ng_print_option "4" "🔥" "Show firewall summary" "Display ufw, firewalld or iptables state"
      ng_print_option "5" "🧬" "Create integrity baseline" "Hash all files under configured watch paths"
      ng_print_option "6" "✅" "Verify integrity baseline" "Check current files against stored hashes"
      ng_print_option "7" "🔒" "Apply simple firewall hardening" "Allow SSH and enable default deny for incoming traffic"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛡 安全巡检" "轻量检查系统暴露面，并做基础加固"
      ng_print_option "1" "📄" "生成安全报告" "汇总认证失败、Web 探测、端口与防火墙状态"
      ng_print_option "2" "🔍" "查看失败登录统计" "统计近期失败登录来源 IP"
      ng_print_option "3" "🌐" "查看可疑 Web 请求" "检查 nginx 访问日志中的常见攻击特征"
      ng_print_option "4" "🔥" "查看防火墙状态" "显示 ufw、firewalld 或 iptables 状态"
      ng_print_option "5" "🧬" "生成完整性基线" "对监控路径下文件生成哈希清单"
      ng_print_option "6" "✅" "校验完整性基线" "按已有哈希清单检查当前文件"
      ng_print_option "7" "🔒" "应用简单防火墙加固" "放行 SSH，并默认拒绝新入站连接"
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
      0) break ;;
      *) ng_t invalid_option ;;
    esac
  done
}
