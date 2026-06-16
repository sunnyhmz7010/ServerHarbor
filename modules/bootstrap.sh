#!/usr/bin/env bash

set -euo pipefail

ng_external_script_prompt() {
  local title="$1"
  local project_url="$2"
  local command_preview="$3"

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Third-party script shortcut: %s\n' "${title}"
    printf '  1. Project source: %s\n' "${project_url}"
    printf '  2. Runtime command:\n'
    printf '     %s\n' "${command_preview}"
    printf '  3. This script is maintained by an external project, not ServerHarbor\n'
    printf 'Continue? [y/N]: '
  else
    printf '第三方脚本快捷入口：%s\n' "${title}"
    printf '  1. 项目来源：%s\n' "${project_url}"
    printf '  2. 即将执行命令：\n'
    printf '     %s\n' "${command_preview}"
    printf '  3. 该脚本由外部项目维护，不属于 ServerHarbor 自身代码\n'
    printf '是否继续？[y/N]: '
  fi
}

ng_run_external_script_shortcut() {
  local title="$1"
  local project_url="$2"
  local script_url="$3"
  local answer=""
  local command_preview="bash <(curl -q -fsSL \"${script_url}?\$(date +%s)\")"

  ng_require_cmd bash curl || return 1
  ng_external_script_prompt "${title}" "${project_url}" "${command_preview}"
  ng_read_line answer || return 130

  if [[ ! "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "External script execution cancelled."
    else
      ng_log "WARN" "已取消外部脚本执行。"
    fi
    return 0
  fi

  bash <(curl -q -fsSL "${script_url}?$(date +%s)")
}

ng_network_tune_shortcuts_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🌍 External Network Tuning Scripts" "Quick launchers for trusted third-party projects"
      ng_print_option "1" "🚀" "bbrv3-lite" "ike-sh maintained TCP tuning shortcut with uncached curl launch"
      ng_print_option "2" "⚙️" "vps-tcp-tune" "Eric86777 maintained TCP tuning shortcut with uncached curl launch"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🌍 第三方网络调优脚本" "为常用外部项目提供快捷启动入口"
      ng_print_option "1" "🚀" "bbrv3-lite" "ike-sh 维护的 TCP 调优脚本快捷入口"
      ng_print_option "2" "⚙️" "vps-tcp-tune" "Eric86777 维护的 TCP 调优脚本快捷入口"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1)
        ng_run_external_script_shortcut \
          "bbrv3-lite" \
          "https://github.com/ike-sh/bbrv3-lite" \
          "https://raw.githubusercontent.com/ike-sh/bbrv3-lite/main/net-tcp-tune.sh"
        ;;
      2)
        ng_run_external_script_shortcut \
          "vps-tcp-tune" \
          "https://github.com/Eric86777/vps-tcp-tune" \
          "https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/refs/heads/main/net-tcp-tune.sh"
        ;;
      0) break ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || return 130
  done
}

ng_configure_dns() {
  ng_require_root || return 1

  local resolv_conf="/etc/resolv.conf"
  local backup_file="${NG_STATE_DIR}/resolv.conf.$(date '+%Y%m%d-%H%M%S').bak"

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
  local backup_file="${NG_STATE_DIR}/sshd_config.$(date '+%Y%m%d-%H%M%S').bak"

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
      ng_report_title 'ServerHarbor Bootstrap Report'
      ng_report_section 'Summary'
      ng_report_kv 'Generated At' "$(ng_timestamp)"
      ng_report_kv 'Host' "${NG_HOSTNAME}"
      ng_report_kv 'Timezone' "${NG_TIMEZONE}"
      ng_report_kv 'DNS' "${NG_DNS_PRIMARY}, ${NG_DNS_SECONDARY}"
      ng_report_kv 'Swap Size' "${NG_SWAP_SIZE_MB}MB"
      ng_report_kv 'Kernel BBR' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
      ng_report_section 'Memory'
      ng_memory_summary
      ng_report_section 'Disk'
      ng_disk_summary
    )"
  else
    content="$(
      ng_report_title 'ServerHarbor 开荒报告'
      ng_report_section '摘要'
      ng_report_kv '生成时间' "$(ng_timestamp)"
      ng_report_kv '主机' "${NG_HOSTNAME}"
      ng_report_kv '时区' "${NG_TIMEZONE}"
      ng_report_kv 'DNS' "${NG_DNS_PRIMARY}, ${NG_DNS_SECONDARY}"
      ng_report_kv 'Swap 大小' "${NG_SWAP_SIZE_MB}MB"
      ng_report_kv '当前拥塞控制' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
      ng_report_section '内存'
      ng_memory_summary
      ng_report_section '磁盘'
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
      ng_print_option "2" "📦" "Install base packages" "curl, wget and common system/network tools"
      ng_print_option "3" "🌐" "Enable BBR" "Write sysctl tuning and reload kernel parameters"
      ng_print_option "4" "🧭" "Configure DNS" "Rewrite /etc/resolv.conf with configured resolvers"
      ng_print_option "5" "🧠" "Configure swap" "Create /swapfile when no swap exists"
      ng_print_option "6" "🔐" "Harden SSH" "Disable password login and tighten SSH defaults"
      ng_print_option "7" "📄" "Generate bootstrap report" "Show timezone, DNS, memory and disk summary"
      ng_print_option "8" "🌍" "External network tuning scripts" "Quick launch bbrv3-lite or vps-tcp-tune"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🚀 新服务器开荒" "面向新机器的一键初始化与基础加固"
      ng_print_option "1" "⚡" "执行完整开荒" "基础软件、时区、BBR、DNS、swap 与 SSH 加固"
      ng_print_option "2" "📦" "安装基础软件" "curl、wget 与常用系统/网络工具"
      ng_print_option "3" "🌐" "启用 BBR" "写入 sysctl 调优并重新加载内核参数"
      ng_print_option "4" "🧭" "配置 DNS" "按配置重写 /etc/resolv.conf"
      ng_print_option "5" "🧠" "配置 swap" "在无 swap 时创建 /swapfile"
      ng_print_option "6" "🔐" "加固 SSH" "禁用密码登录并收紧 SSH 默认项"
      ng_print_option "7" "📄" "生成开荒报告" "输出时区、DNS、内存和磁盘摘要"
      ng_print_option "8" "🌍" "第三方网络调优脚本" "快捷运行 bbrv3-lite 或 vps-tcp-tune"
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
      8) ng_network_tune_shortcuts_menu ;;
      0) break ;;
      *) ng_t invalid_option ;;
    esac
  done
}
