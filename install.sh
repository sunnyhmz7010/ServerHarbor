#!/usr/bin/env bash

set -euo pipefail

PROJECT_NAME="ServerHarbor"
INSTALL_ROOT="/opt/serverharbor"
DATA_ROOT="/etc/serverharbor"
BIN_PATH="/usr/local/bin/shr"
REPO_URL="https://github.com/sunnyhmz7010/ServerHarbor.git"
MANIFEST_PATH="${INSTALL_ROOT}/.serverharbor-install"
INSTALL_OWNER="serverharbor"

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

is_managed_install() {
  [[ -f "${MANIFEST_PATH}" ]]
}

show_existing_install_summary() {
  printf '%s is already installed.\n' "${PROJECT_NAME}"
  printf 'Install root: %s\n' "${INSTALL_ROOT}"
  printf 'Data root   : %s\n' "${DATA_ROOT}"
  printf 'Shortcut    : %s\n' "${BIN_PATH}"
  printf 'To update the local copy, re-run this installer.\n'
}

validate_existing_install_root() {
  if [[ -e "${INSTALL_ROOT}" && ! -d "${INSTALL_ROOT}" ]]; then
    printf 'Refusing to install because %s exists and is not a directory.\n' "${INSTALL_ROOT}" >&2
    exit 1
  fi

  if [[ -d "${INSTALL_ROOT}" && ! -f "${MANIFEST_PATH}" && ! -d "${INSTALL_ROOT}/.git" ]]; then
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

    if ! grep -q "${INSTALL_ROOT}/menu.sh" "${BIN_PATH}" 2>/dev/null; then
      printf 'Refusing to overwrite existing command: %s\n' "${BIN_PATH}" >&2
      printf 'The file does not appear to belong to %s.\n' "${PROJECT_NAME}" >&2
      exit 1
    fi
  fi
}

write_manifest() {
  local current_commit
  current_commit="$(git -C "${INSTALL_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
  cat > "${MANIFEST_PATH}" <<EOF
PROJECT_NAME=${PROJECT_NAME}
INSTALL_OWNER=${INSTALL_OWNER}
INSTALL_ROOT=${INSTALL_ROOT}
DATA_ROOT=${DATA_ROOT}
BIN_PATH=${BIN_PATH}
REPO_URL=${REPO_URL}
COMMIT=${current_commit}
INSTALLED_AT=$(date '+%Y-%m-%d %H:%M:%S')
EOF
  chmod 600 "${MANIFEST_PATH}"
}

install_repo() {
  if [[ -d "${INSTALL_ROOT}/.git" ]]; then
    git -C "${INSTALL_ROOT}" fetch --all --tags
    git -C "${INSTALL_ROOT}" reset --hard origin/main
  else
    rm -rf "${INSTALL_ROOT}"
    git clone "${REPO_URL}" "${INSTALL_ROOT}"
  fi
}

install_launcher() {
  cat > "${BIN_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export SERVERHARBOR_HOME="${DATA_ROOT}"
exec bash "${INSTALL_ROOT}/menu.sh" "\$@"
EOF
  chmod 755 "${BIN_PATH}"
}

seed_data_root() {
  local config_name
  mkdir -p "${DATA_ROOT}/config" "${DATA_ROOT}/logs" "${DATA_ROOT}/reports" "${DATA_ROOT}/state" "${DATA_ROOT}/backups" "${DATA_ROOT}/tmp"
  for config_name in app.conf peers.conf watch.conf; do
    if [[ ! -f "${DATA_ROOT}/config/${config_name}" ]]; then
      cp "${INSTALL_ROOT}/config/${config_name}" "${DATA_ROOT}/config/${config_name}"
    fi
  done
}

main() {
  local already_installed=0

  require_root
  require_cmd git bash

  validate_existing_install_root
  validate_existing_launcher

  if is_managed_install; then
    already_installed=1
    show_existing_install_summary
  fi

  mkdir -p "$(dirname "${BIN_PATH}")"
  install_repo
  chmod +x "${INSTALL_ROOT}/menu.sh" "${INSTALL_ROOT}/run.sh" "${INSTALL_ROOT}/install.sh" "${INSTALL_ROOT}/uninstall.sh"
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
