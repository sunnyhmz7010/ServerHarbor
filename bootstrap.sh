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
  local cpu_arch cpu_model cpu_cores cpu_freq cpu_usage load mem_info swap_info disk_info
  local ipv4_addr isp_info dns_info tcp_algo queue_algo tz_info uptime_info

  cpu_arch=$(uname -m 2>/dev/null || echo "unknown")
  cpu_model=$(awk -F': +' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || lscpu 2>/dev/null | awk -F': +' '/Model name:/ {print $2; exit}' || echo "unknown")
  cpu_cores=$(nproc 2>/dev/null || echo "?")
  cpu_freq=$(awk '/MHz/ {printf "%.1f GHz\n", $4/1000; exit}' /proc/cpuinfo 2>/dev/null || echo "unknown")
  cpu_usage=$(ng_get_cpu_usage)
  load=$(ng_system_load)
  mem_info=$(free -m 2>/dev/null | awk 'NR==2{printf "%dM/%dM (%.1f%%)", $3, $2, $3*100/$2}' || echo "unknown")
  swap_info=$(free -m 2>/dev/null | awk 'NR==3{if($2==0){printf "0M/0M (0%%)"} else {printf "%dM/%dM (%d%%)", $3, $2, $3*100/$2}}' || echo "unknown")
  disk_info=$(df -h / 2>/dev/null | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}' || echo "unknown")
  ipv4_addr=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
  isp_info=$(curl -s --connect-timeout 3 ipinfo.io/org 2>/dev/null || echo "unknown")
  dns_info=$(awk '/^nameserver/{printf "%s ", $2} END {print ""}' /etc/resolv.conf 2>/dev/null || echo "unknown")
  tcp_algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  queue_algo=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
  tz_info=$(timedatectl 2>/dev/null | awk -F': ' '/Time zone:/ {print $2}' || date +%Z 2>/dev/null || echo "unknown")
  uptime_info=$(awk -F. '{d=int($1/86400);h=int(($1%86400)/3600);m=int(($1%3600)/60);if(d>0)printf "%dd ";if(h>0)printf "%dh ";printf "%dm\n", m}' /proc/uptime 2>/dev/null || uptime -p 2>/dev/null || echo "unknown")

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🚀 ServerHarbor Bootstrap Report"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "System Info"
    ng_report_detail "Hostname" "${NG_HOSTNAME}"
    ng_report_detail "OS" "$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")"
    ng_report_detail "Kernel" "$(uname -r)"
    ng_report_detail "Uptime" "${uptime_info}"
    ng_report_separator
    ng_report_section_start "CPU Info"
    ng_report_detail "Architecture" "${cpu_arch}"
    ng_report_detail "Model" "${cpu_model}"
    ng_report_detail "Cores" "${cpu_cores}"
    ng_report_detail "Frequency" "${cpu_freq}"
    ng_report_detail "Usage" "${cpu_usage}%"
    ng_report_detail "Load" "${load}"
    ng_report_separator
    ng_report_section_start "Resource Usage"
    ng_report_detail "Memory" "${mem_info}"
    ng_report_detail "Swap" "${swap_info}"
    ng_report_detail "Disk /" "${disk_info}"
    ng_report_separator
    ng_report_section_start "Network"
    ng_report_detail "IPv4" "${ipv4_addr}"
    ng_report_detail "ISP" "${isp_info}"
    ng_report_detail "DNS" "${dns_info}"
    ng_report_detail "TCP algo" "${tcp_algo} ${queue_algo}"
    ng_report_separator
    ng_report_section_start "Time"
    ng_report_detail "Timezone" "${tz_info}"
    ng_report_detail "Now" "$(date '+%Y-%m-%d %H:%M:%S')"
  else
    ng_report_header "🚀 ServerHarbor 开荒报告"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "系统信息"
    ng_report_detail "主机名" "${NG_HOSTNAME}"
    ng_report_detail "系统版本" "$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")"
    ng_report_detail "内核版本" "$(uname -r)"
    ng_report_detail "运行时长" "${uptime_info}"
    ng_report_separator
    ng_report_section_start "CPU 信息"
    ng_report_detail "CPU 架构" "${cpu_arch}"
    ng_report_detail "CPU 型号" "${cpu_model}"
    ng_report_detail "CPU 核心" "${cpu_cores}"
    ng_report_detail "CPU 频率" "${cpu_freq}"
    ng_report_detail "CPU 占用" "${cpu_usage}%"
    ng_report_detail "系统负载" "${load}"
    ng_report_separator
    ng_report_section_start "资源使用"
    ng_report_detail "物理内存" "${mem_info}"
    ng_report_detail "虚拟内存" "${swap_info}"
    ng_report_detail "磁盘 /" "${disk_info}"
    ng_report_separator
    ng_report_section_start "网络信息"
    ng_report_detail "IPv4" "${ipv4_addr}"
    ng_report_detail "运营商" "${isp_info}"
    ng_report_detail "DNS" "${dns_info}"
    ng_report_detail "TCP 算法" "${tcp_algo} ${queue_algo}"
    ng_report_separator
    ng_report_section_start "系统时间"
    ng_report_detail "时区" "${tz_info}"
    ng_report_detail "当前时间" "$(date '+%Y-%m-%d %H:%M:%S')"
  fi

  local status_text status_color
  local cpu_num mem_num disk_num
  cpu_num=$(echo "${cpu_usage}" | cut -d'.' -f1)
  mem_num=$(free -m 2>/dev/null | awk 'NR==2{printf "%.0f", $3*100/$2}' || echo 0)
  disk_num=$(df / 2>/dev/null | awk 'NR==2{print $5}' | cut -d'%' -f1 || echo 0)
  : "${cpu_num:=0}" "${mem_num:=0}" "${disk_num:=0}"

  if [[ "${cpu_num}" -lt 80 ]] && [[ "${mem_num}" -lt 80 ]] && [[ "${disk_num}" -lt 90 ]]; then
    status_text="$( [[ "${NG_LANG}" == "en" ]] && echo "Normal" || echo "正常" )"
    status_color="${NG_C_OK}"
  else
    status_text="$( [[ "${NG_LANG}" == "en" ]] && echo "Warning" || echo "告警" )"
    status_color="${NG_C_WARN}"
  fi

  ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${status_color}" "${status_text}")"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "CPU:" || echo "CPU:")" "${cpu_usage}% | $([[ "${NG_LANG}" == "en" ]] && echo "Mem:" || echo "内存:")" "${mem_num}% | $([[ "${NG_LANG}" == "en" ]] && echo "Disk:" || echo "磁盘:")" "${disk_num}%"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "SSH:" || echo "SSH:")" "$(ng_service_state sshd)"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Docker:" || echo "Docker:")" "$(ng_service_state docker)"
  ng_report_footer
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
