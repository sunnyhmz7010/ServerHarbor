#!/usr/bin/env bash

set -euo pipefail

PROJECT_NAME="ServerHarbor"
INSTALL_ROOT="/opt/serverharbor"
APP_ROOT="${INSTALL_ROOT}/app"
DATA_ROOT="${INSTALL_ROOT}/data"
BIN_PATH="/usr/local/bin/shr"
ARCHIVE_URL="https://github.com/sunnyhmz7010/ServerHarbor/archive/refs/heads/main.tar.gz"
MANIFEST_PATH="${INSTALL_ROOT}/.serverharbor-install"
INSTALL_OWNER="serverharbor"
TMP_ROOT="${TMPDIR:-/tmp}"
ARCHIVE_PATH="${TMP_ROOT%/}/serverharbor-install.tar.gz"
EXTRACT_DIR="${TMP_ROOT%/}/serverharbor-install-extract"
LANGUAGE="${SERVERHARBOR_LANG:-}"
INTERRUPT_REQUESTED=0
CRITICAL_SECTION=0

handle_preflight_interrupt() {
  printf '\nCancelled / 已取消\n' >&2
  exit 130
}

select_language() {
  local choice

  if [[ -n "${LANGUAGE}" ]]; then
    return 0
  fi

  printf 'Choose language / 选择语言:\n'
  printf '  1. 中文\n'
  printf '  2. English\n'
  printf 'Select [1/2, default/默认: 1] / 请选择：'
  if ! IFS= read -r choice; then
    printf '\n'
    printf 'Cancelled / 已取消\n' >&2
    return 130
  fi

  case "${choice}" in
    2) LANGUAGE="en" ;;
    *) LANGUAGE="zh" ;;
  esac
}

t() {
  local key="$1"
  case "${LANGUAGE}" in
    en)
      case "${key}" in
        need_root) printf 'Please run install.sh as root.\n' ;;
        missing_cmd) printf 'Missing required command: %s\n' "$2" ;;
        continue) printf 'Continue? [y/N]: ' ;;
        plan_title) printf '%s will perform these actions:\n' "${PROJECT_NAME}" ;;
        plan_dep) printf '  1. Ensure curl and tar are available (%s)\n' "$2" ;;
        plan_download) printf '  2. Download source archive from %s\n' "${ARCHIVE_URL}" ;;
        plan_data) printf '  3. Create or preserve data under %s\n' "${DATA_ROOT}" ;;
        plan_launcher) printf '  4. Write managed launcher %s\n' "${BIN_PATH}" ;;
        plan_manifest) printf '  5. Write install manifest %s\n' "${MANIFEST_PATH}" ;;
        dep_ok) printf 'curl and tar already installed' ;;
        dep_missing) printf 'missing curl/tar, will attempt install via %s' "$2" ;;
        dep_installing) printf 'curl or tar not found. Attempting to install required tools via %s...\n' "$2" ;;
        dep_unsupported) printf 'Unable to auto-install curl/tar: unsupported package manager.\n' ;;
        dep_manual) printf 'Please install curl and tar manually and re-run the installer.\n' ;;
        dep_failed) printf 'Required tools were not installed successfully. Please install curl and tar manually.\n' ;;
        already) printf '%s is already installed.\n' "${PROJECT_NAME}" ;;
        install_root) printf 'Install root: %s\n' "${INSTALL_ROOT}" ;;
        app_root) printf 'App root    : %s\n' "${APP_ROOT}" ;;
        data_root) printf 'Data root   : %s\n' "${DATA_ROOT}" ;;
        shortcut) printf 'Shortcut    : %s\n' "${BIN_PATH}" ;;
        rerun_update) printf 'To update the local copy, re-run this installer.\n' ;;
        refuse_not_dir) printf 'Refusing to install because %s exists and is not a directory.\n' "${INSTALL_ROOT}" ;;
        refuse_reuse) printf 'Refusing to reuse existing directory: %s\n' "${INSTALL_ROOT}" ;;
        refuse_reuse_reason) printf 'The directory is not recognized as a managed %s install.\n' "${PROJECT_NAME}" ;;
        refuse_symlink) printf 'Refusing to overwrite symbolic link command: %s\n' "${BIN_PATH}" ;;
        refuse_symlink_reason) printf 'Please remove it manually if you want %s to manage this shortcut.\n' "${PROJECT_NAME}" ;;
        refuse_cmd) printf 'Refusing to overwrite existing command: %s\n' "${BIN_PATH}" ;;
        refuse_cmd_reason) printf 'The file does not appear to belong to %s.\n' "${PROJECT_NAME}" ;;
        bad_archive) printf 'Downloaded archive does not look like a valid %s source tree.\n' "${PROJECT_NAME}" ;;
        cancelled) printf 'Install cancelled.\n' ;;
        updated) printf '%s updated successfully.\n' "${PROJECT_NAME}" ;;
        installed) printf '%s installed successfully.\n' "${PROJECT_NAME}" ;;
        run_cmd) printf 'Run: %s\n' "shr" ;;
        interrupt_deferred) printf '\nInterrupt received. Waiting for the current critical step to finish.\n' ;;
      esac
      ;;
    *)
      case "${key}" in
        need_root) printf '请使用 root 身份运行 install.sh。\n' ;;
        missing_cmd) printf '缺少必要命令：%s\n' "$2" ;;
        continue) printf '是否继续？[y/N]: ' ;;
        plan_title) printf '%s 即将执行以下操作：\n' "${PROJECT_NAME}" ;;
        plan_dep) printf '  1. 确保 curl 和 tar 可用（%s）\n' "$2" ;;
        plan_download) printf '  2. 从 %s 下载源码压缩包\n' "${ARCHIVE_URL}" ;;
        plan_data) printf '  3. 创建或保留数据目录 %s\n' "${DATA_ROOT}" ;;
        plan_launcher) printf '  4. 写入受管快捷命令 %s\n' "${BIN_PATH}" ;;
        plan_manifest) printf '  5. 写入安装清单 %s\n' "${MANIFEST_PATH}" ;;
        dep_ok) printf 'curl 和 tar 已安装' ;;
        dep_missing) printf '缺少 curl/tar，将尝试通过 %s 安装' "$2" ;;
        dep_installing) printf '未找到 curl 或 tar，正在尝试通过 %s 安装所需工具...\n' "$2" ;;
        dep_unsupported) printf '无法自动安装 curl/tar：不支持的包管理器。\n' ;;
        dep_manual) printf '请手动安装 curl 和 tar 后重新运行安装脚本。\n' ;;
        dep_failed) printf '依赖安装未成功，请手动安装 curl 和 tar。\n' ;;
        already) printf '%s 已安装。\n' "${PROJECT_NAME}" ;;
        install_root) printf '安装根目录：%s\n' "${INSTALL_ROOT}" ;;
        app_root) printf '代码目录   ：%s\n' "${APP_ROOT}" ;;
        data_root) printf '数据目录   ：%s\n' "${DATA_ROOT}" ;;
        shortcut) printf '快捷命令   ：%s\n' "${BIN_PATH}" ;;
        rerun_update) printf '如需更新本地代码，请重新运行此安装脚本。\n' ;;
        refuse_not_dir) printf '拒绝安装：%s 已存在且不是目录。\n' "${INSTALL_ROOT}" ;;
        refuse_reuse) printf '拒绝复用现有目录：%s\n' "${INSTALL_ROOT}" ;;
        refuse_reuse_reason) printf '该目录不是受 %s 管理的安装目录。\n' "${PROJECT_NAME}" ;;
        refuse_symlink) printf '拒绝覆盖符号链接命令：%s\n' "${BIN_PATH}" ;;
        refuse_symlink_reason) printf '如果确实要让 %s 管理该快捷命令，请先手动删除它。\n' "${PROJECT_NAME}" ;;
        refuse_cmd) printf '拒绝覆盖现有命令：%s\n' "${BIN_PATH}" ;;
        refuse_cmd_reason) printf '该文件看起来不属于 %s。\n' "${PROJECT_NAME}" ;;
        bad_archive) printf '下载得到的压缩包不是有效的 %s 源码结构。\n' "${PROJECT_NAME}" ;;
        cancelled) printf '已取消安装。\n' ;;
        updated) printf '%s 更新成功。\n' "${PROJECT_NAME}" ;;
        installed) printf '%s 安装成功。\n' "${PROJECT_NAME}" ;;
        run_cmd) printf '启动命令：%s\n' "shr" ;;
        interrupt_deferred) printf '\n已收到中断请求，当前关键步骤完成后再退出。\n' ;;
      esac
      ;;
  esac
}

handle_interrupt() {
  if [[ "${CRITICAL_SECTION}" -eq 1 ]]; then
    INTERRUPT_REQUESTED=1
    t interrupt_deferred >&2
    return 0
  fi
  t cancelled >&2
  exit 130
}

enter_critical_section() {
  CRITICAL_SECTION=1
}

leave_critical_section() {
  CRITICAL_SECTION=0
  if [[ "${INTERRUPT_REQUESTED}" -eq 1 ]]; then
    t cancelled >&2
    exit 130
  fi
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    t need_root >&2
    exit 1
  fi
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      t missing_cmd "${cmd}" >&2
      exit 1
    fi
  done
}

confirm() {
  local answer
  t continue
  if ! IFS= read -r answer; then
    t cancelled
    return 130
  fi
  [[ "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

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

print_install_plan() {
  local pkg_manager dep_note

  pkg_manager="$(detect_pkg_manager)"
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    dep_note="$(t dep_ok)"
  else
    dep_note="$(t dep_missing "${pkg_manager}")"
  fi

  t plan_title
  t plan_dep "${dep_note}"
  t plan_download
  t plan_data
  t plan_launcher
  t plan_manifest
}

ensure_fetch_tools_installed() {
  local manager

  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    return 0
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
      t dep_manual >&2
      exit 1
      ;;
  esac

  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    t dep_failed >&2
    exit 1
  fi
}

is_managed_install() {
  [[ -f "${MANIFEST_PATH}" ]]
}

show_existing_install_summary() {
  t already
  t install_root
  t app_root
  t data_root
  t shortcut
  t rerun_update
}

validate_existing_install_root() {
  if [[ -e "${INSTALL_ROOT}" && ! -d "${INSTALL_ROOT}" ]]; then
    t refuse_not_dir >&2
    exit 1
  fi

  if [[ -d "${INSTALL_ROOT}" && ! -f "${MANIFEST_PATH}" && ! -f "${APP_ROOT}/menu.sh" ]]; then
    t refuse_reuse >&2
    t refuse_reuse_reason >&2
    exit 1
  fi
}

validate_existing_launcher() {
  if [[ -e "${BIN_PATH}" ]]; then
    if [[ -L "${BIN_PATH}" ]]; then
      t refuse_symlink >&2
      t refuse_symlink_reason >&2
      exit 1
    fi

    if ! grep -q "${APP_ROOT}/menu.sh" "${BIN_PATH}" 2>/dev/null; then
      t refuse_cmd >&2
      t refuse_cmd_reason >&2
      exit 1
    fi
  fi
}

write_manifest() {
  cat > "${MANIFEST_PATH}" <<EOF
PROJECT_NAME=${PROJECT_NAME}
INSTALL_OWNER=${INSTALL_OWNER}
INSTALL_ROOT=${INSTALL_ROOT}
APP_ROOT=${APP_ROOT}
DATA_ROOT=${DATA_ROOT}
BIN_PATH=${BIN_PATH}
ARCHIVE_URL=${ARCHIVE_URL}
INSTALLED_AT=$(date '+%Y-%m-%d %H:%M:%S')
EOF
  chmod 600 "${MANIFEST_PATH}"
}

download_and_extract() {
  local extracted_root

  rm -f "${ARCHIVE_PATH}"
  rm -rf "${EXTRACT_DIR}"
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

install_repo() {
  local extracted_root

  extracted_root="$(download_and_extract)"
  rm -rf "${APP_ROOT}"
  mkdir -p "${INSTALL_ROOT}"
  cp -R "${extracted_root}" "${APP_ROOT}"
}

install_launcher() {
  cat > "${BIN_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export SERVERHARBOR_HOME="${DATA_ROOT}"
exec bash "${APP_ROOT}/menu.sh" "\$@"
EOF
  chmod 755 "${BIN_PATH}"
}

seed_data_root() {
  local config_name
  mkdir -p "${DATA_ROOT}/config" "${DATA_ROOT}/logs" "${DATA_ROOT}/reports" "${DATA_ROOT}/state" "${DATA_ROOT}/backups" "${DATA_ROOT}/tmp"
  for config_name in app.conf peers.conf watch.conf; do
    if [[ ! -f "${DATA_ROOT}/config/${config_name}" ]]; then
      cp "${APP_ROOT}/config/${config_name}" "${DATA_ROOT}/config/${config_name}"
    fi
  done
}

main() {
  local already_installed=0

  trap handle_preflight_interrupt INT
  select_language || exit $?
  trap handle_interrupt INT
  require_root
  require_cmd bash

  validate_existing_install_root
  validate_existing_launcher

  if is_managed_install; then
    already_installed=1
    show_existing_install_summary
  fi

  print_install_plan
  if ! confirm; then
    exit 130
  fi

  ensure_fetch_tools_installed

  enter_critical_section
  mkdir -p "$(dirname "${BIN_PATH}")"
  install_repo
  chmod +x "${APP_ROOT}/menu.sh" "${APP_ROOT}/run.sh" "${APP_ROOT}/install.sh" "${APP_ROOT}/uninstall.sh"
  seed_data_root
  write_manifest
  install_launcher
  leave_critical_section

  if [[ "${already_installed}" -eq 1 ]]; then
    t updated
  else
    t installed
  fi
  t run_cmd
}

main "$@"
