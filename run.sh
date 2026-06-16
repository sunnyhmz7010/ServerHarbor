#!/usr/bin/env bash

set -euo pipefail

PROJECT_NAME="ServerHarbor"
ARCHIVE_URL="https://github.com/sunnyhmz7010/ServerHarbor/archive/refs/heads/main.tar.gz"
TMP_ROOT="${TMPDIR:-/tmp}"
WORK_DIR="$(mktemp -d "${TMP_ROOT%/}/serverharbor-run-XXXXXX")"
ARCHIVE_PATH="${WORK_DIR}/serverharbor-run.tar.gz"
EXTRACT_DIR="${WORK_DIR}/extract"
DATA_ROOT="${SERVERHARBOR_HOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/serverharbor}"

cleanup() {
  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT INT TERM

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

print_run_plan() {
  local pkg_manager dep_note

  pkg_manager="$(detect_pkg_manager)"
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    dep_note="curl and tar already installed"
  else
    dep_note="curl or tar missing"
  fi

  printf '%s online run will perform these actions:\n' "${PROJECT_NAME}"
  printf '  1. Use a temporary directory under %s\n' "${TMP_ROOT%/}"
  printf '  2. Download source archive from %s\n' "${ARCHIVE_URL}"
  printf '  3. Use persistent data root %s\n' "${DATA_ROOT}"
  printf '  4. Remove the temporary directory after exit\n'
  if [[ "${EUID}" -eq 0 ]] && { ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; }; then
    printf '  5. Attempt to install curl/tar via %s\n' "${pkg_manager}"
  else
    printf '  5. Dependency status: %s\n' "${dep_note}"
  fi
}

ensure_fetch_tools_installed() {
  local manager

  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${EUID}" -ne 0 ]]; then
    printf 'Missing required commands: curl and/or tar\n' >&2
    printf 'Please install curl and tar or run install.sh with root privileges.\n' >&2
    exit 1
  fi

  manager="$(detect_pkg_manager)"
  printf 'curl or tar not found. Attempting to install them via %s...\n' "${manager}"

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
      exit 1
      ;;
  esac
}

extract_repo() {
  local extracted_root

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

main() {
  local extracted_root

  require_cmd bash
  print_run_plan
  if ! confirm; then
    printf 'Run cancelled.\n'
    exit 0
  fi
  ensure_fetch_tools_installed

  printf 'Fetching %s from %s\n' "${PROJECT_NAME}" "${ARCHIVE_URL}"
  extracted_root="$(extract_repo)"
  chmod +x "${extracted_root}/menu.sh"
  SERVERHARBOR_HOME="${DATA_ROOT}" bash "${extracted_root}/menu.sh" "$@"
}

main "$@"
