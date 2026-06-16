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
    printf 'No auth log found.\n'
    return 0
  fi

  printf '[Top Failed Login IPs]\n'
  grep -Ei 'Failed password|authentication failure' "${auth_log}" 2>/dev/null \
    | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | sort | uniq -c | sort -nr | head
}

ng_scan_web_attacks() {
  local access_log="/var/log/nginx/access.log"

  [[ -f "${access_log}" ]] || {
    printf 'No nginx access log found.\n'
    return 0
  }

  printf '[Suspicious Web Requests]\n'
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
    printf 'No firewall tool found.\n'
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
    printf 'Watch file is missing: %s\n' "${NG_WATCH_FILE}"
    return 1
  }

  : > "${baseline_file}"
  while IFS= read -r watch_path; do
    [[ -n "${watch_path}" && "${watch_path}" != \#* ]] || continue
    if [[ -e "${watch_path}" ]]; then
      find "${watch_path}" -type f -exec sha256sum {} \; >> "${baseline_file}"
    fi
  done < "${NG_WATCH_FILE}"

  printf 'Integrity baseline written to %s\n' "${baseline_file}"
}

ng_integrity_verify() {
  if [[ ! -f "${NG_INTEGRITY_DB}" ]]; then
    printf 'No integrity baseline found. Create one first.\n'
    return 1
  fi

  (cd / && sha256sum -c "${NG_INTEGRITY_DB}") 2>/dev/null || true
}

ng_security_report() {
  local content

  content="$(
    printf 'ServerMesh Security Report\n'
    printf 'Generated at: %s\n' "$(ng_timestamp)"
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
    ng_print_header "Security Guard"
    cat <<'EOF'
1. Run security report
2. Show failed login statistics
3. Show suspicious web requests
4. Show firewall summary
5. Apply simple firewall hardening
0. Back
EOF
    printf 'Select: '
    read -r choice

    case "${choice}" in
      1) ng_security_report ;;
      2) ng_scan_auth_failures ;;
      3) ng_scan_web_attacks ;;
      4) ng_firewall_summary ;;
      5) if ng_prompt_yes_no "Apply simple firewall hardening now?"; then ng_simple_firewall_hardening; fi ;;
      0) break ;;
      *) printf 'Invalid option.\n' ;;
    esac
  done
}

ng_integrity_menu() {
  local choice

  while true; do
    ng_print_header "Integrity Monitor"
    cat <<'EOF'
1. Create integrity baseline
2. Verify integrity baseline
0. Back
EOF
    printf 'Select: '
    read -r choice

    case "${choice}" in
      1) ng_integrity_create_baseline ;;
      2) ng_integrity_verify ;;
      0) break ;;
      *) printf 'Invalid option.\n' ;;
    esac
  done
}
