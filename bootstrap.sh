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

ng_bootstrap_report() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🚀 ServerHarbor Bootstrap Report"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "System Info"
    ng_report_kv_styled "Uptime" "$(uptime -p 2>/dev/null || uptime)"
    ng_report_kv_styled "Kernel" "$(uname -r)"
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
    ng_report_section_start "系统信息"
    ng_report_kv_styled "运行时长" "$(uptime -p 2>/dev/null || uptime)"
    ng_report_kv_styled "内核版本" "$(uname -r)"
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

ng_bootstrap_menu() {
  local choice

  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🚀 System Bootstrap" "Server provisioning and optimization"
      ng_print_option "1" "📦" "Install base packages" "curl, socat, wget, sudo, iptables"
      ng_print_option "2" "🐳" "Install Docker" "Auto-detect region for mirror"
      ng_print_option "3" "🚀" "bbrv3-lite" "Lightweight BBR v3 / XanMod / TCP tuning script"
      ng_print_option "4" "⚙️" "vps-tcp-tune" "BBR3+FQ TCP tuning script for VPS optimization"
      ng_print_option "5" "📊" "System status" "Check CPU, memory, disk and alerts"
      ng_print_option "6" "📄" "Generate report" "Show system summary"
      if [[ "${NG_RUNTIME_MODE}" == "installed" ]]; then
        ng_print_option "7" "🔄" "Migrate data" "Migrate from online to installed version"
      fi
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🚀 系统开荒" "服务器初始化与优化"
      ng_print_option "1" "📦" "基础软件安装" "curl、socat、wget、sudo、iptables"
      ng_print_option "2" "🐳" "Docker 安装" "自动检测地区使用镜像"
      ng_print_option "3" "🚀" "bbrv3-lite" "轻量级 BBR v3 / XanMod / TCP 网络调优脚本"
      ng_print_option "4" "⚙️" "vps-tcp-tune" "BBR3+FQ TCP 网络调优脚本，一键优化 VPS 网络"
      ng_print_option "5" "📊" "系统状态" "查看 CPU、内存、磁盘和告警"
      ng_print_option "6" "📄" "生成报告" "输出系统摘要"
      if [[ "${NG_RUNTIME_MODE}" == "installed" ]]; then
        ng_print_option "7" "🔄" "数据迁移" "从在线版迁移到安装版"
      fi
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_require_root && ng_install_base_packages ;;
      2)
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
      3)
        ng_run_external_script_shortcut \
          "bbrv3-lite" \
          "https://github.com/ike-sh/bbrv3-lite" \
          "https://raw.githubusercontent.com/ike-sh/bbrv3-lite/main/net-tcp-tune.sh"
        ;;
      4)
        ng_run_external_script_shortcut \
          "vps-tcp-tune" \
          "https://github.com/Eric86777/vps-tcp-tune" \
          "https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/refs/heads/main/net-tcp-tune.sh"
        ;;
      5) ng_show_system_status ;;
      6) ng_bootstrap_report ;;
      7) ng_trigger_migration ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac
    
    ng_press_enter || return 130
  done
}
