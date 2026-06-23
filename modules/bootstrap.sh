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
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || return 130
  done
}

ng_configure_dns() {
  ng_require_root || return 1

  local resolv_conf="/etc/resolv.conf"
  local backup_file="${NG_STATE_DIR}/resolv.conf.$(date '+%Y%m%d-%H%M%S').bak"

  # Check if DNS is already configured with the same values
  if grep -q "nameserver ${NG_DNS_PRIMARY}" "${resolv_conf}" 2>/dev/null \
     && grep -q "nameserver ${NG_DNS_SECONDARY}" "${resolv_conf}" 2>/dev/null; then
    ng_log "INFO" "DNS already configured. Skip."
    return 0
  fi

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
  
  # Create swapfile
  fallocate -l "${NG_SWAP_SIZE_MB}M" "${swap_file}" 2>/dev/null || dd if=/dev/zero of="${swap_file}" bs=1M count="${NG_SWAP_SIZE_MB}" 2>/dev/null
  
  # Verify swapfile was created
  if [[ ! -f "${swap_file}" ]]; then
    ng_log "ERROR" "Failed to create swapfile."
    return 1
  fi

  chmod 600 "${swap_file}"
  
  # mkswap and swapon - if either fails, clean up and return error
  if ! mkswap "${swap_file}" 2>/dev/null; then
    ng_log "ERROR" "Failed to create swap space. Cleaning up."
    rm -f "${swap_file}"
    return 1
  fi
  
  if ! swapon "${swap_file}" 2>/dev/null; then
    ng_log "ERROR" "Failed to activate swap. Cleaning up."
    rm -f "${swap_file}"
    return 1
  fi

  # Only write fstab on success
  grep -q '^/swapfile' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
  ng_log "INFO" "Swap created at ${swap_file} with size ${NG_SWAP_SIZE_MB}MB"
}

ng_enable_bbr() {
  ng_require_root || return 1

  local sysctl_file="/etc/sysctl.d/99-serverharbor-bbr.conf"
  
  # Check if BBR is already enabled
  local current_congestion
  current_congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  if [[ "${current_congestion}" == "bbr" ]] && [[ -f "${sysctl_file}" ]]; then
    ng_log "INFO" "BBR already enabled. Skip."
    return 0
  fi
  
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

  # Check if SSH keys exist to avoid lockout
  local has_ssh_keys=0
  if [[ -f ~/.ssh/authorized_keys ]] && [[ -s ~/.ssh/authorized_keys ]]; then
    has_ssh_keys=1
  fi

  if [[ "${has_ssh_keys}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "No SSH authorized_keys found. Disabling password login may lock you out!"
      printf 'Warning: No SSH authorized_keys found at ~/.ssh/authorized_keys\n'
      printf 'Disabling password authentication may prevent future login.\n'
      if ! ng_prompt_yes_no "Continue with SSH hardening anyway?"; then
        ng_log "INFO" "SSH hardening cancelled by user."
        return 0
      fi
    else
      ng_log "WARN" "未找到 SSH authorized_keys，禁用密码登录可能导致无法登录！"
      printf '警告：未找到 ~/.ssh/authorized_keys\n'
      printf '禁用密码认证可能导致以后无法登录服务器。\n'
      if ! ng_prompt_yes_no "是否继续执行 SSH 加固？"; then
        ng_log "INFO" "用户取消了 SSH 加固。"
        return 0
      fi
    fi
  fi

  cp "${sshd_config}" "${backup_file}"
  sed -i \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' \
    -e 's/^#\?X11Forwarding.*/X11Forwarding no/' \
    "${sshd_config}"

  if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl restart sshd 2>/dev/null && ! systemctl restart ssh 2>/dev/null; then
      ng_log "WARN" "Failed to restart SSH service. Please restart manually."
    fi
  fi

  ng_log "INFO" "SSH hardening rules applied."
}

ng_bootstrap_report() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🚀 ServerHarbor Bootstrap Report"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "System Configuration"
    ng_report_kv_styled "Timezone" "${NG_TIMEZONE}"
    ng_report_kv_styled "DNS" "${NG_DNS_PRIMARY}, ${NG_DNS_SECONDARY}"
    ng_report_kv_styled "Swap Size" "${NG_SWAP_SIZE_MB}MB"
    ng_report_kv_styled "Kernel BBR" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    ng_report_section_start "Memory"
    free -h 2>/dev/null | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_section_start "Disk"
    df -hT 2>/dev/null | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_footer
  else
    ng_report_header "🚀 ServerHarbor 开荒报告"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "系统配置"
    ng_report_kv_styled "时区" "${NG_TIMEZONE}"
    ng_report_kv_styled "DNS" "${NG_DNS_PRIMARY}, ${NG_DNS_SECONDARY}"
    ng_report_kv_styled "Swap 大小" "${NG_SWAP_SIZE_MB}MB"
    ng_report_kv_styled "当前拥塞控制" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    ng_report_section_start "内存"
    free -h 2>/dev/null | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_section_start "磁盘"
    df -hT 2>/dev/null | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_footer
  fi
}

ng_bootstrap_full() {
  ng_require_root || return 1
  local errors=0
  
  ng_install_base_packages || { ng_log "WARN" "Base packages installation failed."; ((errors++)); true; }
  ng_set_timezone || { ng_log "WARN" "Timezone configuration failed."; ((errors++)); true; }
  ng_enable_bbr || { ng_log "WARN" "BBR enable failed."; ((errors++)); true; }
  ng_configure_dns || { ng_log "WARN" "DNS configuration failed."; ((errors++)); true; }
  ng_configure_swap || { ng_log "WARN" "Swap configuration failed."; ((errors++)); true; }
  
  if [[ "${NG_LANG}" == "en" ]]; then
    if ng_prompt_yes_no "SSH hardening may disable password login. Continue?"; then
      ng_harden_ssh || { ng_log "WARN" "SSH hardening failed."; ((errors++)); true; }
    fi
  else
    if ng_prompt_yes_no "SSH 加固可能禁用密码登录，是否继续？"; then
      ng_harden_ssh || { ng_log "WARN" "SSH hardening failed."; ((errors++)); true; }
    fi
  fi
  
  ng_bootstrap_report
  
  if [[ "${errors}" -gt 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "Bootstrap completed with ${errors} error(s)."
    else
      ng_log "WARN" "开荒完成，但有 ${errors} 个错误。"
    fi
    return 1
  fi
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_log "INFO" "Bootstrap completed successfully."
  else
    ng_log "INFO" "开荒完成。"
  fi
}

ng_bootstrap_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🚀 System Bootstrap" "Server provisioning, monitoring and network tools"
      ng_print_option "1" "⚡" "Run full bootstrap" "Base packages, timezone, BBR, DNS, swap and SSH hardening"
      ng_print_option "2" "📦" "Install base packages" "curl, wget and common system/network tools"
      ng_print_option "3" "🌐" "Enable BBR" "Write sysctl tuning and reload kernel parameters"
      ng_print_option "4" "🧭" "Configure DNS" "Rewrite /etc/resolv.conf with configured resolvers"
      ng_print_option "5" "🧠" "Configure swap" "Create /swapfile when no swap exists"
      ng_print_option "6" "🔐" "Harden SSH" "Disable password login and tighten SSH defaults"
      ng_print_option "7" "📊" "System monitor" "CPU, memory, disk usage and alerts"
      ng_print_option "8" "🌐" "Network tools" "Ping, traceroute, DNS lookup, port scan"
      ng_print_option "9" "📄" "Generate report" "Show system summary report"
      ng_print_option "10" "🌍" "External scripts" "Quick launch bbrv3-lite or vps-tcp-tune"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🚀 系统开荒" "服务器初始化、监控与网络工具"
      ng_print_option "1" "⚡" "执行完整开荒" "基础软件、时区、BBR、DNS、swap 与 SSH 加固"
      ng_print_option "2" "📦" "安装基础软件" "curl、wget 与常用系统/网络工具"
      ng_print_option "3" "🌐" "启用 BBR" "写入 sysctl 调优并重新加载内核参数"
      ng_print_option "4" "🧭" "配置 DNS" "按配置重写 /etc/resolv.conf"
      ng_print_option "5" "🧠" "配置 swap" "在无 swap 时创建 /swapfile"
      ng_print_option "6" "🔐" "加固 SSH" "禁用密码登录并收紧 SSH 默认项"
      ng_print_option "7" "📊" "系统监控" "CPU、内存、磁盘使用率与告警"
      ng_print_option "8" "🌐" "网络工具" "Ping、路由追踪、DNS 查询、端口扫描"
      ng_print_option "9" "📄" "生成报告" "输出系统摘要报告"
      ng_print_option "10" "🌍" "第三方脚本" "快捷运行 bbrv3-lite 或 vps-tcp-tune"
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
      7) ng_monitor_menu ;;
      8) ng_network_menu ;;
      9) ng_bootstrap_report ;;
      10) ng_network_tune_shortcuts_menu ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac
  done
}
