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

  if [[ "${NG_LANG}" == "en" ]]; then
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
  else
    content="$(
      printf 'ServerHarbor 开荒报告\n'
      printf '生成时间：%s\n' "$(ng_timestamp)"
      printf '主机        : %s\n' "${NG_HOSTNAME}"
      printf '时区        : %s\n' "${NG_TIMEZONE}"
      printf 'DNS         : %s, %s\n' "${NG_DNS_PRIMARY}" "${NG_DNS_SECONDARY}"
      printf 'Swap 大小   : %sMB\n' "${NG_SWAP_SIZE_MB}"
      printf '当前拥塞控制: %s\n' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
      printf '\n[内存]\n'
      ng_memory_summary
      printf '\n[磁盘]\n'
      ng_disk_summary
    )"
  fi

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
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🚀 Server Bootstrap" "First-run provisioning for a fresh server"
      ng_print_option "1" "⚡" "Run full bootstrap" "Base packages, timezone, BBR, DNS, swap and SSH hardening"
      ng_print_option "2" "📦" "Install base packages" "curl, wget, git, rsync, cron and common network tools"
      ng_print_option "3" "🌐" "Enable BBR" "Write sysctl tuning and reload kernel parameters"
      ng_print_option "4" "🧭" "Configure DNS" "Rewrite /etc/resolv.conf with configured resolvers"
      ng_print_option "5" "🧠" "Configure swap" "Create /swapfile when no swap exists"
      ng_print_option "6" "🔐" "Harden SSH" "Disable password login and tighten SSH defaults"
      ng_print_option "7" "📄" "Generate bootstrap report" "Show timezone, DNS, memory and disk summary"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🚀 新服务器开荒" "面向新机器的一键初始化与基础加固"
      ng_print_option "1" "⚡" "执行完整开荒" "基础软件、时区、BBR、DNS、swap 与 SSH 加固"
      ng_print_option "2" "📦" "安装基础软件" "curl、wget、git、rsync、cron 与常用网络工具"
      ng_print_option "3" "🌐" "启用 BBR" "写入 sysctl 调优并重新加载内核参数"
      ng_print_option "4" "🧭" "配置 DNS" "按配置重写 /etc/resolv.conf"
      ng_print_option "5" "🧠" "配置 swap" "在无 swap 时创建 /swapfile"
      ng_print_option "6" "🔐" "加固 SSH" "禁用密码登录并收紧 SSH 默认项"
      ng_print_option "7" "📄" "生成开荒报告" "输出时区、DNS、内存和磁盘摘要"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_bootstrap_full ;;
      2) ng_require_root && ng_install_base_packages ;;
      3) ng_enable_bbr ;;
      4) ng_configure_dns ;;
      5) ng_configure_swap ;;
      6)
        if [[ "${NG_LANG}" == "en" ]]; then
          if ng_prompt_yes_no "This may disable password login. Continue?"; then
            ng_harden_ssh
          fi
        else
          if ng_prompt_yes_no "该操作可能禁用密码登录，是否继续？"; then
            ng_harden_ssh
          fi
        fi
        ;;
      7) ng_bootstrap_report ;;
      0) break ;;
      *) ng_t invalid_option ;;
    esac
  done
}
