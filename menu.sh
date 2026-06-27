#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载各功能模块
# shellcheck source=common.sh
source "${PROJECT_ROOT}/common.sh"
# shellcheck source=bootstrap.sh
source "${PROJECT_ROOT}/bootstrap.sh"
# shellcheck source=security.sh
source "${PROJECT_ROOT}/security.sh"
# shellcheck source=nodes.sh
source "${PROJECT_ROOT}/nodes.sh"

# 初始化运行环境（创建目录、加载配置、初始化主题）
ng_init_environment

# 中断信号处理
handle_menu_interrupt() {
  exit 130
}

trap handle_menu_interrupt INT

# 判断当前是否为在线运行模式
ng_is_online_runtime() {
  [[ "${SERVERHARBOR_RUNTIME:-}" == "online" ]]
}

# 自更新：在线模式下退出并触发刷新，安装模式下调用 install.sh --update
ng_self_update() {
  local installer="${PROJECT_ROOT}/install.sh"

  if ng_is_online_runtime; then
    # 在线模式通过退出码触发 run.sh 重新下载最新源码
    exit "${SERVERHARBOR_REFRESH_EXIT_CODE:-42}"
  fi

  if [[ ! -f "${installer}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "install.sh not found. Unable to run managed update."
    else
      ng_log "ERROR" "未找到 install.sh，无法执行受管更新。"
    fi
    return 1
  fi

  chmod +x "${installer}" 2>/dev/null || true
  bash "${installer}" --update
}

# CLI 命令行模式：支持定时任务参数直接执行功能
run_cli_mode() {
  case "${1:-}" in
    --cron-probe)
      # 定时探测所有节点状态
      ng_probe_all_peers
      exit 0
      ;;
    --cron-security)
      # 定时生成安全报告
      ng_security_report
      exit 0
      ;;
    --cron-alerts)
      # 定时检查系统资源告警
      set +e
      ng_check_alerts
      exit $?
      ;;
    "")
      return 0
      ;;
    *)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Unknown argument: %s\n' "$1"
      else
        printf '未知参数: %s\n' "$1"
      fi
      exit 1
      ;;
  esac
}

# 显示程序横幅信息（标题、主机名、数据目录、节点数）
show_banner() {
  clear || true

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_title_box "🚢 ServerHarbor" "Decentralized multi-server bootstrap, probe and security toolkit"
    ng_print_stat "Host" "${NG_HOSTNAME}" "🖥"
    ng_print_stat "Data Root" "${NG_DATA_ROOT}" "📦"
    ng_print_stat "Total Nodes" "$(ng_total_node_count)" "🛰"
  else
    ng_print_title_box "🚢 ServerHarbor" "去中心化多服务器开荒、探测与安全工具箱"
    ng_print_stat "主机" "${NG_HOSTNAME}" "🖥"
    ng_print_stat "数据目录" "${NG_DATA_ROOT}" "📦"
    ng_print_stat "总节点数" "$(ng_total_node_count)" "🛰"
  fi

  printf '\n'
}

# 检测是否为安装版（存在安装清单文件）
ng_is_installed() {
  [[ -f "/opt/serverharbor/.serverharbor-install" ]]
}

# 卸载入口：调用 uninstall.sh 执行卸载
ng_uninstall() {
  local uninstaller="${PROJECT_ROOT}/uninstall.sh"

  if [[ ! -f "${uninstaller}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "uninstall.sh not found."
    else
      ng_log "ERROR" "未找到 uninstall.sh。"
    fi
    return 1
  fi

  chmod +x "${uninstaller}" 2>/dev/null || true
  SERVERHARBOR_LANG="${NG_LANG}" bash "${uninstaller}"
  exit 0
}

# 显示主菜单选项
show_menu() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_option "1" "🚀" "System bootstrap" "Base packages / Docker / network tuning scripts"
    ng_print_option "2" "🛡" "Security guard" "Auth logs / web attacks / firewall / integrity / security score"
    ng_print_option "3" "🛰" "Node management" "Multi-server management / batch commands / config sync"
    ng_print_option "4" "♻️" "Update" "Download latest source and restart"
    if ng_is_installed; then
      ng_print_option "5" "🗑" "Uninstall" "Remove ServerHarbor from this system"
    fi
    ng_print_option "0" "↩" "Exit"
  else
    ng_print_option "1" "🚀" "系统开荒" "基础软件 / Docker / 网络调优脚本"
    ng_print_option "2" "🛡" "安全卫士" "认证日志 / Web 攻击 / 防火墙 / 完整性 / 安全评分"
    ng_print_option "3" "🛰" "节点管理" "多服务器管理 / 批量命令 / 配置同步"
    ng_print_option "4" "♻️" "更新" "下载最新源码并重启"
    if ng_is_installed; then
      ng_print_option "5" "🗑" "卸载" "从系统中移除 ServerHarbor"
    fi
    ng_print_option "0" "↩" "退出"
  fi

  printf '\n'
  ng_print_menu_hint
}

# 主循环：显示横幅和菜单，读取用户输入并分发到各功能模块
main() {
  local choice

  while true; do
    show_banner
    show_menu
    printf '\n'
    ng_t select
    ng_read_line choice || exit 130

    case "${choice}" in
      1) ng_bootstrap_menu ;;    # 系统开荒
      2) ng_security_menu ;;     # 安全卫士
      3) ng_node_menu ;;         # 节点管理
      4) ng_self_update ;;       # 自更新
      5)
        if ng_is_installed; then
          ng_uninstall           # 卸载
        else
          ng_t invalid_option
        fi
        ;;
      0) exit 0 ;;
      *) ng_t invalid_option ;;
    esac
  done
}

# 先处理 CLI 命令行模式，再进入交互式菜单
run_cli_mode "${1:-}"
main
