#!/usr/bin/env bash

set -euo pipefail

ng_configure_dns() {
  ng_require_root || return 1

  local resolv_conf="/etc/resolv.conf"
  local backup_file="${NG_BACKUP_DIR}/resolv.conf.$(date '+%Y%m%d-%H%M%S').bak"

  cp "${resolv_conf}" "${backup_file}" 2>/dev/null || true
  {
    printf 'nameserver %s\n' "${NG_DNS_PRIMARY}"
    printf 'nameserver %s\n' "${NG_DNS_SECONDARY}"
  } > "${resolv_conf}"

  ng_log "INFO" "DNS configured: ${NG_DNS_PRIMARY}, ${NG_DNS_SECONDARY}"
}

ng_configure_swap() {
  ng_require_root || return 1

  if swapon --show | grep -q '.'; then
    ng_log "INFO" "Swap already exists. Skip creation."
    return 0
  fi

  local swap_file="/swapfile"
  fallocate -l "${NG_SWAP_SIZE_MB}M" "${swap_file}" 2>/dev/null || dd if=/dev/zero of="${swap_file}" bs=1M count="${NG_SWAP_SIZE_MB}"
  chmod 600 "${swap_file}"
  mkswap "${swap_file}"
  swapon "${swap_file}"
  grep -q '^/swapfile' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab

  ng_log "INFO" "Swap created at ${swap_file} with size ${NG_SWAP_SIZE_MB}MB"
}

ng_enable_bbr() {
  ng_require_root || return 1

  local sysctl_file="/etc/sysctl.d/99-nebulaguard-bbr.conf"
  cat > "${sysctl_file}" <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null 2>&1 || true

  ng_log "INFO" "BBR tuning file written to ${sysctl_file}"
}

ng_set_timezone() {
  ng_require_root || return 1

  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone "${NG_TIMEZONE}" || true
    ng_log "INFO" "Timezone set to ${NG_TIMEZONE}"
  else
    ng_log "WARN" "timedatectl not available. Skip timezone configuration."
  fi
}

ng_harden_ssh() {
  ng_require_root || return 1

  local sshd_config="/etc/ssh/sshd_config"
  local backup_file="${NG_BACKUP_DIR}/sshd_config.$(date '+%Y%m%d-%H%M%S').bak"

  [[ -f "${sshd_config}" ]] || {
    ng_log "WARN" "sshd_config not found. Skip SSH hardening."
    return 0
  }

  cp "${sshd_config}" "${backup_file}"
  sed -i \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' \
    -e 's/^#\?X11Forwarding.*/X11Forwarding no/' \
    "${sshd_config}"

  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
  fi

  ng_log "INFO" "SSH hardening rules applied."
}

ng_bootstrap_report() {
  local content

  content="$(
    printf 'ServerHarbor Bootstrap Report\n'
    printf 'Generated at: %s\n' "$(ng_timestamp)"
    printf 'Host        : %s\n' "${NG_HOSTNAME}"
    printf 'Timezone    : %s\n' "${NG_TIMEZONE}"
    printf 'DNS         : %s, %s\n' "${NG_DNS_PRIMARY}" "${NG_DNS_SECONDARY}"
    printf 'Swap size   : %sMB\n' "${NG_SWAP_SIZE_MB}"
    printf 'Kernel BBR  : %s\n' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    printf '\n[Memory]\n'
    ng_memory_summary
    printf '\n[Disk]\n'
    ng_disk_summary
  )"

  ng_write_report "bootstrap" "${content}" >/dev/null
  printf '%s\n' "${content}"
}

ng_bootstrap_full() {
  ng_require_root || return 1
  ng_install_base_packages
  ng_set_timezone
  ng_enable_bbr
  ng_configure_dns
  ng_configure_swap
  ng_harden_ssh
  ng_bootstrap_report
}

ng_bootstrap_menu() {
  local choice

  while true; do
    ng_print_header "Server Bootstrap"
    cat <<'EOF'
1. Run full bootstrap
2. Install base packages
3. Enable BBR
4. Configure DNS
5. Configure swap
6. Harden SSH
7. Generate bootstrap report
0. Back
EOF
    printf 'Select: '
    read -r choice

    case "${choice}" in
      1) ng_bootstrap_full ;;
      2) ng_require_root && ng_install_base_packages ;;
      3) ng_enable_bbr ;;
      4) ng_configure_dns ;;
      5) ng_configure_swap ;;
      6) if ng_prompt_yes_no "This may disable password login. Continue?"; then ng_harden_ssh; fi ;;
      7) ng_bootstrap_report ;;
      0) break ;;
      *) printf 'Invalid option.\n' ;;
    esac
  done
}
