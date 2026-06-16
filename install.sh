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

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    printf 'Please run install.sh as root.\n' >&2
    exit 1
  fi
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      printf 'Missing required command: %s\n' "${cmd}" >&2
      exit 1
    fi
  done
}

confirm() {
  local answer
  printf 'Continue? [y/N]: '
  read -r answer
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
    dep_note="curl and tar already installed"
  else
    dep_note="missing curl/tar, will attempt install via ${pkg_manager}"
  fi

  printf '%s will perform these actions:\n' "${PROJECT_NAME}"
  printf '  1. Ensure curl and tar are available (%s)\n' "${dep_note}"
  printf '  2. Download source archive from %s\n' "${ARCHIVE_URL}"
  printf '  3. Create or preserve data under %s\n' "${DATA_ROOT}"
  printf '  4. Write managed launcher %s\n' "${BIN_PATH}"
  printf '  5. Write install manifest %s\n' "${MANIFEST_PATH}"
}

ensure_fetch_tools_installed() {
  local manager

  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    return 0
  fi

  manager="$(detect_pkg_manager)"
  printf 'curl or tar not found. Attempting to install required tools via %s...\n' "${manager}"

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
      printf 'Unable to auto-install curl/tar: unsupported package manager.\n' >&2
      printf 'Please install curl and tar manually and re-run the installer.\n' >&2
      exit 1
      ;;
  esac

  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    printf 'Required tools were not installed successfully. Please install curl and tar manually.\n' >&2
    exit 1
  fi
}

is_managed_install() {
  [[ -f "${MANIFEST_PATH}" ]]
}

show_existing_install_summary() {
  printf '%s is already installed.\n' "${PROJECT_NAME}"
  printf 'Install root: %s\n' "${INSTALL_ROOT}"
  printf 'App root    : %s\n' "${APP_ROOT}"
  printf 'Data root   : %s\n' "${DATA_ROOT}"
  printf 'Shortcut    : %s\n' "${BIN_PATH}"
  printf 'To update the local copy, re-run this installer.\n'
}

validate_existing_install_root() {
  if [[ -e "${INSTALL_ROOT}" && ! -d "${INSTALL_ROOT}" ]]; then
    printf 'Refusing to install because %s exists and is not a directory.\n' "${INSTALL_ROOT}" >&2
    exit 1
  fi

  if [[ -d "${INSTALL_ROOT}" && ! -f "${MANIFEST_PATH}" && ! -f "${APP_ROOT}/menu.sh" ]]; then
    printf 'Refusing to reuse existing directory: %s\n' "${INSTALL_ROOT}" >&2
    printf 'The directory is not recognized as a managed %s install.\n' "${PROJECT_NAME}" >&2
    exit 1
  fi
}

validate_existing_launcher() {
  if [[ -e "${BIN_PATH}" ]]; then
    if [[ -L "${BIN_PATH}" ]]; then
      printf 'Refusing to overwrite symbolic link command: %s\n' "${BIN_PATH}" >&2
      printf 'Please remove it manually if you want %s to manage this shortcut.\n' "${PROJECT_NAME}" >&2
      exit 1
    fi

    if ! grep -q "${APP_ROOT}/menu.sh" "${BIN_PATH}" 2>/dev/null; then
      printf 'Refusing to overwrite existing command: %s\n' "${BIN_PATH}" >&2
      printf 'The file does not appear to belong to %s.\n' "${PROJECT_NAME}" >&2
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
    printf 'Downloaded archive does not look like a valid %s source tree.\n' "${PROJECT_NAME}" >&2
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
    printf 'Install cancelled.\n'
    exit 0
  fi

  ensure_fetch_tools_installed

  mkdir -p "$(dirname "${BIN_PATH}")"
  install_repo
  chmod +x "${APP_ROOT}/menu.sh" "${APP_ROOT}/run.sh" "${APP_ROOT}/install.sh" "${APP_ROOT}/uninstall.sh"
  seed_data_root
  write_manifest
  install_launcher

  if [[ "${already_installed}" -eq 1 ]]; then
    printf '%s updated successfully.\n' "${PROJECT_NAME}"
  else
    printf '%s installed successfully.\n' "${PROJECT_NAME}"
  fi
  printf 'Run: %s\n' "shr"
}

main "$@"
