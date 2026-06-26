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

handle_preflight_interrupt() {
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
  if ! IFS= read -r choice < /dev/tty; then
    LANGUAGE="zh"
    return 0
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
        continue) printf 'Continue? [Y/n]: ' ;;
        plan_title) printf '%s will perform these actions:\n' "${PROJECT_NAME}" ;;
        plan_dep) printf '  5. Dependency status: %s\n' "$2" ;;
        plan_download) printf '  1. Download source archive from %s\n' "${ARCHIVE_URL}" ;;
        plan_data) printf '  2. Create or preserve data under %s\n' "${DATA_ROOT}" ;;
        plan_launcher) printf '  3. Write managed launcher %s\n' "${BIN_PATH}" ;;
        plan_manifest) printf '  4. Write install manifest %s\n' "${MANIFEST_PATH}" ;;
        dep_ok) printf 'curl and tar already installed' ;;
        dep_missing) printf 'curl or tar missing' ;;
        dep_installing) printf 'curl or tar not found. Attempting to install via %s...\n' "$2" ;;
        dep_unsupported) printf 'Unable to auto-install curl/tar: unsupported package manager.\n' ;;
        dep_manual) printf 'Please install curl and tar manually and re-run the installer.\n' ;;
        dep_failed) printf 'Required tools were not installed successfully. Please install curl and tar manually.\n' ;;
        already) printf '%s is already installed.\n' "${PROJECT_NAME}" ;;
        already_latest) printf '%s is already up to date. No files were replaced.\n' "${PROJECT_NAME}" ;;
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
      esac
      ;;
    *)
      case "${key}" in
        need_root) printf '请使用 root 身份运行 install.sh。\n' ;;
        missing_cmd) printf '缺少必要命令：%s\n' "$2" ;;
        continue) printf '是否继续？[Y/n]: ' ;;
        plan_title) printf '%s 将执行以下操作：\n' "${PROJECT_NAME}" ;;
        plan_dep) printf '  5. 依赖状态：%s\n' "$2" ;;
        plan_download) printf '  1. 从 %s 下载源码压缩包\n' "${ARCHIVE_URL}" ;;
        plan_data) printf '  2. 创建或保留数据目录 %s\n' "${DATA_ROOT}" ;;
        plan_launcher) printf '  3. 写入受管快捷命令 %s\n' "${BIN_PATH}" ;;
        plan_manifest) printf '  4. 写入安装清单 %s\n' "${MANIFEST_PATH}" ;;
        dep_ok) printf 'curl 和 tar 已安装' ;;
        dep_missing) printf '缺少 curl 或 tar' ;;
        dep_installing) printf '未找到 curl 或 tar，正在尝试通过 %s 安装...\n' "$2" ;;
        dep_unsupported) printf '无法自动安装 curl/tar：不支持的包管理器。\n' ;;
        dep_manual) printf '请手动安装 curl 和 tar 后重新运行安装脚本。\n' ;;
        dep_failed) printf '依赖安装未成功，请手动安装 curl 和 tar。\n' ;;
        already) printf '%s 已安装。\n' "${PROJECT_NAME}" ;;
        already_latest) printf '%s 已是最新版本，未替换任何文件。\n' "${PROJECT_NAME}" ;;
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
      esac
      ;;
  esac
}

handle_interrupt() {
  exit 130
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
  if ! IFS= read -r answer < /dev/tty; then
    return 130
  fi
  [[ -z "${answer}" || "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]
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
  t plan_download
  t plan_data
  t plan_launcher
  t plan_manifest
  t plan_dep "${dep_note}"
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

calc_tree_hash() {
  local target_dir="$1"

  find "${target_dir}" -type f ! -path '*/.git/*' -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | awk '{print $1}'
}

is_same_source_tree() {
  local extracted_root="$1"
  local current_hash
  local extracted_hash

  [[ -d "${APP_ROOT}" ]] || return 1

  current_hash="$(calc_tree_hash "${APP_ROOT}")"
  extracted_hash="$(calc_tree_hash "${extracted_root}")"
  [[ -n "${current_hash}" && "${current_hash}" == "${extracted_hash}" ]]
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
  mkdir -p "${DATA_ROOT}/logs" "${DATA_ROOT}/reports" "${DATA_ROOT}/state"
  if [[ ! -f "${DATA_ROOT}/serverharbor.conf" ]]; then
    cp "${APP_ROOT}/serverharbor.conf" "${DATA_ROOT}/serverharbor.conf"
  fi
}

migrate_online_data() {
  local online_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/serverharbor"

  if [[ ! -d "${online_dir}" ]]; then
    return 0
  fi

  local has_data=0
  [[ -f "${online_dir}/servers.json" ]] && has_data=1
  [[ -f "${online_dir}/serverharbor.conf" ]] && has_data=1
  [[ -d "${online_dir}/state" ]] && [[ -n "$(ls -A "${online_dir}/state" 2>/dev/null)" ]] && has_data=1
  [[ -d "${online_dir}/reports" ]] && [[ -n "$(ls -A "${online_dir}/reports" 2>/dev/null)" ]] && has_data=1
  [[ -d "${online_dir}/logs" ]] && [[ -n "$(ls -A "${online_dir}/logs" 2>/dev/null)" ]] && has_data=1

  if [[ "${has_data}" -eq 0 ]]; then
    return 0
  fi

  printf '\n'
  if [[ "${LANGUAGE}" == "en" ]]; then
    printf 'Online version data detected at:\n'
    printf '  %s\n' "${online_dir}"
    printf '\nThis data can be migrated to the installed location:\n'
    printf '  %s\n' "${DATA_ROOT}"
    printf '\nOptions:\n'
    printf '  [y] Migrate data to installed version\n'
    printf '  [n] Skip, keep data in online directory\n'
    printf 'Choose [Y/n]: '
  else
    printf '检测到在线版数据目录：\n'
    printf '  %s\n' "${online_dir}"
    printf '\n可将数据迁移到安装版目录：\n'
    printf '  %s\n' "${DATA_ROOT}"
    printf '\n选项：\n'
    printf '  [y] 迁移数据到安装版\n'
    printf '  [n] 跳过，数据保留在在线版目录\n'
    printf '请选择 [Y/n]: '
  fi

  local answer
  if ! IFS= read -r answer < /dev/tty; then
    return 0
  fi
  if [[ -n "${answer}" && ! "${answer}" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    return 0
  fi

  if [[ "${LANGUAGE}" == "en" ]]; then
    printf '\nMigrating data...\n'
  else
    printf '\n正在迁移数据...\n'
  fi

  mkdir -p "${DATA_ROOT}/state" "${DATA_ROOT}/reports" "${DATA_ROOT}/logs"

  for conf_name in servers.json serverharbor.conf; do
    if [[ -f "${online_dir}/${conf_name}" ]]; then
      cp -f "${online_dir}/${conf_name}" "${DATA_ROOT}/${conf_name}" 2>/dev/null || true
      printf '  ✓ %s\n' "${conf_name}"
    fi
  done

  for sub_dir in state reports logs; do
    if [[ -d "${online_dir}/${sub_dir}" ]] && [[ -n "$(ls -A "${online_dir}/${sub_dir}" 2>/dev/null)" ]]; then
      cp -rf "${online_dir}/${sub_dir}/"* "${DATA_ROOT}/${sub_dir}/" 2>/dev/null || true
      if [[ "${LANGUAGE}" == "en" ]]; then
        printf '  ✓ %s (%d files)\n' "${sub_dir}" "$(ls -1 "${online_dir}/${sub_dir}" 2>/dev/null | wc -l)"
      else
        printf '  ✓ %s（%d 个文件）\n' "${sub_dir}" "$(ls -1 "${online_dir}/${sub_dir}" 2>/dev/null | wc -l)"
      fi
    fi
  done

  if [[ "${LANGUAGE}" == "en" ]]; then
    printf '\n✓ Migration completed!\n'
  else
    printf '\n✓ 数据迁移完成！\n'
  fi
}

LOCK_FILE="/var/lock/serverharbor.lock"

acquire_lock() {
  # Create lock file atomically to avoid symlink attacks
  install -m 600 /dev/null "${LOCK_FILE}" 2>/dev/null || true
  exec {lock_fd}>"${LOCK_FILE}"
  if ! flock -n "${lock_fd}" 2>/dev/null; then
    if [[ "${LANGUAGE}" == "en" ]]; then
      printf 'Another install/uninstall process is running. Aborting.\n' >&2
    else
      printf '另一个安装/卸载进程正在运行，已中止。\n' >&2
    fi
    exit 1
  fi
}

cleanup() {
  rm -f "${ARCHIVE_PATH}"
  rm -rf "${EXTRACT_DIR}"
  rm -f "${LOCK_FILE}"
}

main() {
  local already_installed=0
  local extracted_root=""
  local update_mode=0

  # Set up EXIT trap for cleanup
  trap cleanup EXIT

  if [[ "${1:-}" == "--update" ]]; then
    update_mode=1
  fi

  trap handle_preflight_interrupt INT
  select_language || exit $?
  trap handle_interrupt INT
  require_root
  require_cmd bash
  acquire_lock

  validate_existing_install_root
  validate_existing_launcher

  if is_managed_install && [[ "${update_mode}" -eq 0 ]]; then
    exec bash "${APP_ROOT}/menu.sh" < /dev/tty
  fi

  if is_managed_install; then
    already_installed=1
  fi

  print_install_plan
  if ! confirm; then
    exit 130
  fi

  ensure_fetch_tools_installed

  extracted_root="$(download_and_extract)"

  if [[ "${already_installed}" -eq 1 ]] && is_same_source_tree "${extracted_root}"; then
    rm -f "${ARCHIVE_PATH}"
    rm -rf "${EXTRACT_DIR}"
    t already_latest
    exit 0
  fi

  mkdir -p "$(dirname "${BIN_PATH}")"
  # Defensive check before rm -rf
  if [[ -n "${APP_ROOT}" && -d "${APP_ROOT}" ]]; then
    rm -rf "${APP_ROOT}"
  fi
  mkdir -p "${INSTALL_ROOT}"
  cp -R "${extracted_root}" "${APP_ROOT}"
  chmod +x "${APP_ROOT}/menu.sh" "${APP_ROOT}/run.sh" "${APP_ROOT}/install.sh" "${APP_ROOT}/uninstall.sh"
  seed_data_root
  if [[ "${already_installed}" -eq 0 ]]; then
    migrate_online_data
  fi
  write_manifest
  install_launcher
  rm -f "${ARCHIVE_PATH}"
  rm -rf "${EXTRACT_DIR}"

  if [[ "${already_installed}" -eq 1 ]]; then
    t updated
  else
    t installed
  fi
  t run_cmd
}

main "$@"
