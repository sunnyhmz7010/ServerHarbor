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
  
  # Also check sshd_config.d directory for overrides
  local config_d="/etc/ssh/sshd_config.d"
  if [[ -d "${config_d}" ]]; then
    local override_files
    override_files=$(grep -rl "PasswordAuthentication\|PermitRootLogin" "${config_d}/" 2>/dev/null || true)
    if [[ -n "${override_files}" ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        ng_log "WARN" "Found SSH config overrides in ${config_d}: ${override_files}"
        printf 'Warning: SSH config overrides found in %s\n' "${config_d}"
        printf 'These files may override the hardening settings:\n'
        echo "${override_files}" | while IFS= read -r f; do printf '  - %s\n' "$f"; done
      else
        ng_log "WARN" "在 ${config_d} 中发现 SSH 配置覆盖: ${override_files}"
        printf '警告：在 %s 中发现 SSH 配置覆盖\n' "${config_d}"
        printf '这些文件可能覆盖加固设置：\n'
        echo "${override_files}" | while IFS= read -r f; do printf '  - %s\n' "$f"; done
      fi
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl restart sshd 2>/dev/null && ! systemctl restart ssh 2>/dev/null; then
      ng_log "WARN" "Failed to restart SSH service. Please restart manually."
    fi
  fi
  
  # Verify actual SSH config
  if command -v sshd >/dev/null 2>&1; then
    local actual_config
    actual_config=$(sshd -T 2>/dev/null | grep -E "^(passwordauthentication|permitrootlogin|x11forwarding)" || true)
    if [[ -n "${actual_config}" ]]; then
      ng_log "INFO" "Actual SSH config: ${actual_config}"
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

ng_run_step() {
  local label="$1"
  shift
  if "$@"; then
    return 0
  else
    ng_log "WARN" "${label}"
    STEP_ERRORS=$((STEP_ERRORS + 1))
    return 0
  fi
}

ng_bootstrap_full() {
  ng_require_root || return 1
  STEP_ERRORS=0
  
  ng_run_step "Base packages installation failed" ng_install_base_packages
  ng_run_step "Timezone configuration failed" ng_set_timezone
  ng_run_step "BBR enable failed" ng_enable_bbr
  ng_run_step "DNS configuration failed" ng_configure_dns
  ng_run_step "Swap configuration failed" ng_configure_swap
  
  if [[ "${NG_LANG}" == "en" ]]; then
    if ng_prompt_yes_no "SSH hardening may disable password login. Continue?"; then
      ng_run_step "SSH hardening failed" ng_harden_ssh
    fi
  else
    if ng_prompt_yes_no "SSH 加固可能禁用密码登录，是否继续？"; then
      ng_run_step "SSH hardening failed" ng_harden_ssh
    fi
  fi
  
  ng_bootstrap_report
  
  if [[ "${STEP_ERRORS}" -gt 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "Bootstrap completed with ${STEP_ERRORS} error(s)."
    else
      ng_log "WARN" "开荒完成，但有 ${STEP_ERRORS} 个错误。"
    fi
    return 1
  fi
  
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_log "INFO" "Bootstrap completed successfully."
  else
    ng_log "INFO" "开荒完成。"
  fi
}

ng_bootstrap_oneclick() {
  ng_require_root || return 1

  # ========== Step 1: Base packages ==========
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Step 1/4: Base Software Installation"
    printf 'Default packages: curl socat wget sudo iptables\n\n'
    printf '  [1] Use default list (install directly)\n'
    printf '  [2] Custom list (add/remove packages)\n'
    printf '  [3] Skip this step\n\n'
  else
    ng_print_header "步骤 1/4: 基础软件安装"
    printf '默认安装：curl socat wget sudo iptables\n\n'
    printf '  [1] 使用默认列表（直接安装）\n'
    printf '  [2] 自定义列表（添加/删除软件）\n'
    printf '  [3] 跳过此步骤\n\n'
  fi

  local pkg_choice
  ng_read_line pkg_choice || return 130

  case "${pkg_choice}" in
    1)
      apt update -y && apt upgrade -y && apt install -y curl socat wget sudo iptables
      ;;
    2)
      local default_packages="curl socat wget sudo iptables"
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Current list: %s\n\n' "${default_packages}"
        printf 'Packages to remove (space-separated, Enter to skip): '
      else
        printf '当前列表：%s\n\n' "${default_packages}"
        printf '输入要删除的软件（空格分隔，直接回车跳过）：'
      fi
      local remove_list
      ng_read_line remove_list || return 130

      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Packages to add (space-separated, Enter to skip): '
      else
        printf '输入要添加的软件（空格分隔，直接回车跳过）：'
      fi
      local add_list
      ng_read_line add_list || return 130

      local final_packages="${default_packages}"
      if [[ -n "${remove_list}" ]]; then
        for pkg in ${remove_list}; do
          final_packages=$(echo "${final_packages}" | sed "s/\b${pkg}\b//g")
        done
      fi
      if [[ -n "${add_list}" ]]; then
        final_packages="${final_packages} ${add_list}"
      fi

      if [[ "${NG_LANG}" == "en" ]]; then
        printf '\nWill install: %s\n\n' "${final_packages}"
      else
        printf '\n将安装：%s\n\n' "${final_packages}"
      fi
      apt update -y && apt upgrade -y && apt install -y ${final_packages}
      ;;
    3)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Skipped base software installation.\n'
      else
        printf '已跳过基础软件安装\n'
      fi
      ;;
    *)
      ng_t invalid_option
      return 1
      ;;
  esac

  # ========== Step 2: Docker ==========
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Step 2/4: Docker Installation"
  else
    ng_print_header "步骤 2/4: Docker 安装"
  fi

  if ng_prompt_yes_no "$( [[ "${NG_LANG}" == "en" ]] && printf 'Install Docker?' || printf '是否安装 Docker？' )"; then
    local country
    country=$(curl -s ipinfo.io/country 2>/dev/null || echo "unknown")

    if [[ "${country}" == "CN" ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Detected China server, installing Docker with Aliyun mirror...\n'
      else
        printf '检测到中国服务器，使用阿里云镜像安装 Docker...\n'
      fi
      curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
    else
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Installing Docker with official source...\n'
      else
        printf '使用官方源安装 Docker...\n'
      fi
      curl -fsSL https://get.docker.com | sh
    fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Skipped Docker installation.\n'
    else
      printf '已跳过 Docker 安装\n'
    fi
  fi

  # ========== Step 3: TCP/BBR ==========
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Step 3/4: TCP/BBR Optimization"
    printf 'Description:\n'
    printf '  - BBR v3 kernel: Install XanMod kernel, requires restart\n'
    printf '  - TCP tuning: Optimize network buffers and queue algorithms (includes DNS purification)\n\n'
  else
    ng_print_header "步骤 3/4: TCP/BBR 优化"
    printf '说明：\n'
    printf '  - BBR v3 内核：安装 XanMod 内核，需要重启才能生效\n'
    printf '  - TCP 调优：优化网络缓冲区和队列算法，包含 DNS 净化\n\n'
  fi

  local install_kernel=0
  local install_tcp=0
  local allow_swap=0

  if ng_prompt_yes_no "$( [[ "${NG_LANG}" == "en" ]] && printf 'Install BBR v3 kernel?' || printf '是否安装 BBR v3 内核？' )"; then
    install_kernel=1
  fi

  if ng_prompt_yes_no "$( [[ "${NG_LANG}" == "en" ]] && printf 'Execute TCP tuning?' || printf '是否执行 TCP 调优？' )"; then
    install_tcp=1
  fi

  if [[ "${install_tcp}" -eq 1 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\nNote: bbrv3-lite TCP tuning will automatically configure swap based on memory.\n'
    else
      printf '\n注意：bbrv3-lite TCP 调优会自动根据内存配置 swap。\n'
    fi
    if ng_prompt_yes_no "$( [[ "${NG_LANG}" == "en" ]] && printf 'Allow automatic swap configuration?' || printf '是否允许自动配置 swap？' )"; then
      allow_swap=1
    fi
  fi

  if [[ "${install_kernel}" -eq 1 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\nInstalling BBR v3 kernel...\n'
    else
      printf '\n正在安装 BBR v3 内核...\n'
    fi
    bash <(curl -fsSL "https://raw.githubusercontent.com/ike-sh/bbrv3-lite/main/net-tcp-tune.sh?$(date +%s)") -i
  fi

  if [[ "${install_tcp}" -eq 1 ]]; then
    if [[ "${allow_swap}" -eq 1 ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '\nExecuting TCP tuning (with swap configuration)...\n'
      else
        printf '\n正在执行 TCP 调优（包含 swap 配置）...\n'
      fi
      echo "10" | bash <(curl -fsSL "https://raw.githubusercontent.com/ike-sh/bbrv3-lite/main/net-tcp-tune.sh?$(date +%s)")
    else
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '\nExecuting TCP tuning (without swap configuration)...\n'
        printf 'Note: Using menu option 3 for TCP-only tuning.\n'
      else
        printf '\n正在执行 TCP 调优（不包含 swap 配置）...\n'
        printf '注意：使用菜单选项 3 进行仅 TCP 调优。\n'
      fi
      echo "3" | bash <(curl -fsSL "https://raw.githubusercontent.com/ike-sh/bbrv3-lite/main/net-tcp-tune.sh?$(date +%s)")
    fi
  fi

  if [[ "${install_kernel}" -eq 0 && "${install_tcp}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Skipped TCP/BBR optimization.\n'
    else
      printf '已跳过 TCP/BBR 优化\n'
    fi
  fi

  # ========== Step 4: Report ==========
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Step 4/4: Generate Report"
  else
    ng_print_header "步骤 4/4: 生成开荒报告"
  fi
  ng_bootstrap_report

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_log "INFO" "One-click full flow completed."
  else
    ng_log "INFO" "一键全流程完成。"
  fi
}

ng_bootstrap_menu() {
  local choice

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🚀 System Bootstrap" "Server provisioning and optimization"
      ng_print_option "1" "⚡" "One-click full flow" "Base packages + Docker + TCP/BBR + Report"
      ng_print_option "2" "📦" "Install base packages" "curl, socat, wget, sudo, iptables"
      ng_print_option "3" "🐳" "Install Docker" "Auto-detect region for mirror"
      ng_print_option "4" "🚀" "TCP/BBR optimization" "bbrv3-lite kernel or TCP tuning"
      ng_print_option "5" "🌐" "Configure DNS" "Rewrite /etc/resolv.conf"
      ng_print_option "6" "🧠" "Configure swap" "Create /swapfile"
      ng_print_option "7" "🔐" "Harden SSH" "Disable password login"
      ng_print_option "8" "📄" "Generate report" "Show system summary"
      ng_print_option "9" "🌍" "External scripts" "Quick launch third-party scripts"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🚀 系统开荒" "服务器初始化与优化"
      ng_print_option "1" "⚡" "一键全流程" "基础软件 + Docker + TCP/BBR + 报告"
      ng_print_option "2" "📦" "基础软件安装" "curl、socat、wget、sudo、iptables"
      ng_print_option "3" "🐳" "Docker 安装" "自动检测地区使用镜像"
      ng_print_option "4" "🚀" "TCP/BBR 优化" "bbrv3-lite 内核或 TCP 调优"
      ng_print_option "5" "🌐" "配置 DNS" "重写 /etc/resolv.conf"
      ng_print_option "6" "🧠" "配置 swap" "创建 /swapfile"
      ng_print_option "7" "🔐" "加固 SSH" "禁用密码登录"
      ng_print_option "8" "📄" "生成报告" "输出系统摘要"
      ng_print_option "9" "🌍" "第三方脚本" "快捷运行外部脚本"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_bootstrap_oneclick ;;
      2) ng_require_root && ng_install_base_packages ;;
      3)
        if ng_prompt_yes_no "$( [[ "${NG_LANG}" == "en" ]] && printf 'Install Docker?' || printf '是否安装 Docker？' )"; then
          local country
          country=$(curl -s ipinfo.io/country 2>/dev/null || echo "unknown")
          if [[ "${country}" == "CN" ]]; then
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
          else
            curl -fsSL https://get.docker.com | sh
          fi
        fi
        ;;
      4)
        if [[ "${NG_LANG}" == "en" ]]; then
          printf '  [1] Install BBR v3 kernel (requires restart)\n'
          printf '  [2] TCP tuning only\n'
          printf '  [3] Skip\n'
        else
          printf '  [1] 安装 BBR v3 内核（需要重启）\n'
          printf '  [2] 仅 TCP 调优\n'
          printf '  [3] 跳过\n'
        fi
        local bbr_choice
        ng_read_line bbr_choice || return 130
        case "${bbr_choice}" in
          1) bash <(curl -fsSL "https://raw.githubusercontent.com/ike-sh/bbrv3-lite/main/net-tcp-tune.sh?$(date +%s)") -i ;;
          2)
            if [[ "${NG_LANG}" == "en" ]]; then
              printf '\nNote: bbrv3-lite TCP tuning will automatically configure swap based on memory.\n'
            else
              printf '\n注意：bbrv3-lite TCP 调优会自动根据内存配置 swap。\n'
            fi
            if ng_prompt_yes_no "$( [[ "${NG_LANG}" == "en" ]] && printf 'Allow automatic swap configuration?' || printf '是否允许自动配置 swap？' )"; then
              echo "10" | bash <(curl -fsSL "https://raw.githubusercontent.com/ike-sh/bbrv3-lite/main/net-tcp-tune.sh?$(date +%s)")
            else
              echo "3" | bash <(curl -fsSL "https://raw.githubusercontent.com/ike-sh/bbrv3-lite/main/net-tcp-tune.sh?$(date +%s)")
            fi
            ;;
          *) ;;
        esac
        ;;
      5) ng_configure_dns ;;
      6) ng_configure_swap ;;
      7)
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
      8) ng_bootstrap_report ;;
      9) ng_network_tune_shortcuts_menu ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac
  done
}
