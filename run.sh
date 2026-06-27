#!/usr/bin/env bash

set -euo pipefail

PROJECT_NAME="ServerHarbor"
ARCHIVE_URL="https://github.com/sunnyhmz7010/ServerHarbor/archive/refs/heads/main.tar.gz"
TMP_ROOT="${TMPDIR:-/tmp}"
WORK_DIR="$(mktemp -d "${TMP_ROOT%/}/serverharbor-run-XXXXXX")"
ARCHIVE_PATH="${WORK_DIR}/serverharbor-run.tar.gz"
EXTRACT_DIR="${WORK_DIR}/extract"
DATA_ROOT="${SERVERHARBOR_HOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/serverharbor}"
CONFIG_FILE="${DATA_ROOT}/serverharbor.conf"
LANGUAGE="${SERVERHARBOR_LANG:-}"
REFRESH_EXIT_CODE=42  # 特殊退出码，用于触发刷新

# 中断信号处理
handle_preflight_interrupt() {
  exit 130
}

# 将语言设置持久化到配置文件
persist_language() {
  mkdir -p "${DATA_ROOT}"
  if [[ -f "${CONFIG_FILE}" ]] && grep -q '^NG_LANG=' "${CONFIG_FILE}" 2>/dev/null; then
    sed -i "s/^NG_LANG=.*/NG_LANG=\"${LANGUAGE}\"/" "${CONFIG_FILE}"
  elif [[ -f "${CONFIG_FILE}" ]]; then
    printf 'NG_LANG="%s"\n' "${LANGUAGE}" >> "${CONFIG_FILE}"
  else
    printf '# ServerHarbor Configuration\nNG_LANG="%s"\n' "${LANGUAGE}" > "${CONFIG_FILE}"
  fi
}

# 语言选择：优先读取环境变量，其次读取配置文件，最后交互式选择
select_language() {
  local choice

  # 尝试从配置文件读取已保存的语言设置
  if [[ -z "${LANGUAGE}" && -f "${CONFIG_FILE}" ]]; then
    local conf_lang
    conf_lang=$(grep '^NG_LANG=' "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d'"' -f2)
    if [[ "${conf_lang}" == "en" || "${conf_lang}" == "zh" ]]; then
      LANGUAGE="${conf_lang}"
    fi
  fi

  if [[ -n "${LANGUAGE}" ]]; then
    return 0
  fi

  # 交互式语言选择
  printf 'Choose language / 选择语言:\n'
  printf '  1. 中文\n'
  printf '  2. English\n'
  printf 'Select [1/2, default/默认: 1] / 请选择：'
  if ! IFS= read -r choice < /dev/tty; then
    LANGUAGE="zh"
    return 0
  fi

  case "${choice}" in
    2) LANGUAGE="en" ;;
    *) LANGUAGE="zh" ;;
  esac

  persist_language
}

# 多语言文本翻译函数
t() {
  local key="$1"
  case "${LANGUAGE}" in
    en)
      case "${key}" in
        missing_cmd) printf 'Missing required command: %s\n' "$2" ;;
        continue) printf 'Continue? [Y/n]: ' ;;
        plan_title) printf '%s online run will perform these actions:\n' "${PROJECT_NAME}" ;;
        plan_tmp) printf '  1. Use a temporary directory under %s\n' "${TMP_ROOT%/}" ;;
        plan_download) printf '  2. Download source archive from %s\n' "${ARCHIVE_URL}" ;;
        plan_data) printf '  3. Use persistent data root %s\n' "${DATA_ROOT}" ;;
        plan_cleanup) printf '  4. Remove the temporary directory after exit\n' ;;
        plan_dep_install) printf '  5. Attempt to install curl/tar via %s\n' "$2" ;;
        plan_dep_status) printf '  5. Dependency status: %s\n' "$2" ;;
        dep_ok) printf 'curl and tar already installed' ;;
        dep_missing) printf 'curl or tar missing' ;;
        dep_need_root) printf 'Missing required commands: curl and/or tar\n' ;;
        dep_need_root_hint) printf 'Please install curl and tar or run install.sh with root privileges.\n' ;;
        dep_installing) printf 'curl or tar not found. Attempting to install them via %s...\n' "$2" ;;
        dep_unsupported) printf 'Unable to auto-install curl/tar: unsupported package manager.\n' ;;
        bad_archive) printf 'Downloaded archive does not look like a valid %s source tree.\n' "${PROJECT_NAME}" ;;
        cancelled) printf 'Run cancelled.\n' ;;
        fetching) printf 'Fetching %s from %s\n' "${PROJECT_NAME}" "${ARCHIVE_URL}" ;;
      esac
      ;;
    *)
      case "${key}" in
        missing_cmd) printf '缺少必要命令：%s\n' "$2" ;;
        continue) printf '是否继续？[Y/n]: ' ;;
        plan_title) printf '%s 在线运行将执行以下操作：\n' "${PROJECT_NAME}" ;;
        plan_tmp) printf '  1. 使用临时目录根 %s\n' "${TMP_ROOT%/}" ;;
        plan_download) printf '  2. 从 %s 下载源码压缩包\n' "${ARCHIVE_URL}" ;;
        plan_data) printf '  3. 使用持久化数据目录 %s\n' "${DATA_ROOT}" ;;
        plan_cleanup) printf '  4. 退出后删除临时目录\n' ;;
        plan_dep_install) printf '  5. 尝试通过 %s 安装 curl/tar\n' "$2" ;;
        plan_dep_status) printf '  5. 依赖状态：%s\n' "$2" ;;
        dep_ok) printf 'curl 和 tar 已安装' ;;
        dep_missing) printf '缺少 curl 或 tar' ;;
        dep_need_root) printf '缺少必要命令：curl 和/或 tar\n' ;;
        dep_need_root_hint) printf '请先安装 curl 和 tar，或使用具备 root 权限的 install.sh。\n' ;;
        dep_installing) printf '未找到 curl 或 tar，正在尝试通过 %s 安装...\n' "$2" ;;
        dep_unsupported) printf '无法自动安装 curl/tar：不支持的包管理器。\n' ;;
        bad_archive) printf '下载得到的压缩包不是有效的 %s 源码结构。\n' "${PROJECT_NAME}" ;;
        cancelled) printf '已取消运行。\n' ;;
        fetching) printf '正在从 %s 获取 %s\n' "${ARCHIVE_URL}" "${PROJECT_NAME}" ;;
      esac
      ;;
  esac
}

# 中断信号处理
handle_interrupt() {
  exit 130
}

# 退出时清理临时目录
cleanup() {
  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT INT TERM

# 检查必要命令是否存在
require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      t missing_cmd "${cmd}" >&2
      exit 1
    fi
  done
}

# 确认提示
confirm() {
  local answer
  t continue
  if ! IFS= read -r answer < /dev/tty; then
    return 130
  fi
  [[ -z "${answer}" || "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# 检测系统包管理器
detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  else
    echo "unknown"
  fi
}

# 打印在线运行的操作计划
print_run_plan() {
  local pkg_manager dep_note

  pkg_manager="$(detect_pkg_manager)"
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    dep_note="$(t dep_ok)"
  else
    dep_note="$(t dep_missing)"
  fi

  t plan_title
  t plan_tmp
  t plan_download
  t plan_data
  t plan_cleanup
  # 以 root 身份运行时可以自动安装依赖
  if [[ "${EUID}" -eq 0 ]] && { ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; }; then
    t plan_dep_install "${pkg_manager}"
  else
    t plan_dep_status "${dep_note}"
  fi

  # 提示安装版与在线版数据独立
  if [[ -f "/opt/serverharbor/.serverharbor-install" ]]; then
    if [[ "${LANGUAGE}" == "en" ]]; then
      printf '\n  ⚠ ServerHarbor is installed. Installed data: /opt/serverharbor/data\n'
      printf '    Online data and installed data are separate. Changes here won'\''t affect installed version.\n'
    else
      printf '\n  ⚠ ServerHarbor 已安装。安装版数据: /opt/serverharbor/data\n'
      printf '    在线版数据与安装版数据独立，在线版的修改不会影响安装版。\n'
    fi
  fi
}

# 确保 curl 和 tar 已安装（需要 root 权限时自动安装）
ensure_fetch_tools_installed() {
  local manager

  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${EUID}" -ne 0 ]]; then
    t dep_need_root >&2
    t dep_need_root_hint >&2
    exit 1
  fi

  manager="$(detect_pkg_manager)"
  t dep_installing "${manager}"

  case "${manager}" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y curl tar
      ;;
    dnf)
      dnf install -y curl tar
      ;;
    yum)
      yum install -y curl tar
      ;;
    *)
      t dep_unsupported >&2
      exit 1
      ;;
  esac
}

# 下载并解压源码压缩包，返回解压后的根目录路径
extract_repo() {
  local extracted_root

  mkdir -p "${EXTRACT_DIR}"
  curl -fsSL "${ARCHIVE_URL}" -o "${ARCHIVE_PATH}"
  tar -xzf "${ARCHIVE_PATH}" -C "${EXTRACT_DIR}"
  extracted_root="$(find "${EXTRACT_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "${extracted_root}" || ! -f "${extracted_root}/menu.sh" ]]; then
    t bad_archive >&2
    exit 1
  fi
  printf '%s\n' "${extracted_root}"
}

# 主流程
main() {
  local extracted_root
  local menu_exit_code=0
  local refresh_requested=0

  trap handle_preflight_interrupt INT
  
  # 刷新模式下跳过语言选择和确认步骤
  if [[ "${SERVERHARBOR_REFRESHING:-}" != "1" ]]; then
    select_language || exit $?
    persist_language
    trap handle_interrupt INT
    require_cmd bash
    print_run_plan
    if ! confirm; then
      exit 130
    fi
  else
    trap handle_interrupt INT
    require_cmd bash
  fi
  
  ensure_fetch_tools_installed

  # 下载最新源码
  t fetching
  extracted_root="$(extract_repo)"
  chmod +x "${extracted_root}/menu.sh"

  # 运行菜单程序，传入所有参数
  menu_exit_code=0
  set +e
  SERVERHARBOR_HOME="${DATA_ROOT}" SERVERHARBOR_LANG="${LANGUAGE}" SERVERHARBOR_RUNTIME="online" SERVERHARBOR_REFRESH_EXIT_CODE="${REFRESH_EXIT_CODE}" bash "${extracted_root}/menu.sh" "$@"
  menu_exit_code=$?
  set -e

  # 检测是否需要刷新（退出码为 42）
  if [[ "${menu_exit_code}" -eq "${REFRESH_EXIT_CODE}" ]]; then
    refresh_requested=1
  fi

  # 刷新重试机制：重新下载最新源码并运行
  if [[ "${refresh_requested}" -eq 1 ]]; then
    local max_retries="${SERVERHARBOR_MAX_REFRESH_RETRIES:-3}"
    local current_retry="${SERVERHARBOR_REFRESH_RETRY:-0}"

    # 防止无限刷新循环
    if [[ "${current_retry}" -ge "${max_retries}" ]]; then
      if [[ "${LANGUAGE}" == "en" ]]; then
        printf 'Maximum refresh retries (%d) reached. Aborting.\n' "${max_retries}" >&2
      else
        printf '已达到最大刷新重试次数（%d），已中止。\n' "${max_retries}" >&2
      fi
      exit 1
    fi

    # 重新下载 run.sh 并用 exec 替换当前进程
    export SERVERHARBOR_REFRESHING=1
    export SERVERHARBOR_REFRESH_RETRY=$((current_retry + 1))
    local refresh_script="${TMP_ROOT%/}/serverharbor-refresh-$$.sh"
    curl -q -fsSL "https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/run.sh?$(date +%s)" -o "${refresh_script}"
    chmod +x "${refresh_script}"
    exec bash "${refresh_script}" "$@"
  fi

  # 退出后询问是否删除持久化数据目录
  if [[ -d "${DATA_ROOT}" ]]; then
    local answer
    if [[ "${LANGUAGE}" == "en" ]]; then
      printf 'Remove persistent data directory %s? [y/N]: ' "${DATA_ROOT}"
    else
      printf '是否删除持久化数据目录 %s？[y/N]：' "${DATA_ROOT}"
    fi
    if IFS= read -r answer < /dev/tty; then
      if [[ "${answer}" =~ ^[Yy] ]]; then
        if [[ "${LANGUAGE}" == "en" ]]; then
          printf 'Removing persistent data directory: %s\n' "${DATA_ROOT}"
        else
          printf '正在删除持久化数据目录：%s\n' "${DATA_ROOT}"
        fi
        rm -rf "${DATA_ROOT}"
      fi
    fi
  fi

  exit "${menu_exit_code}"
}

main "$@"
