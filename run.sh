#!/usr/bin/env bash

set -euo pipefail

PROJECT_NAME="ServerHarbor"
REPO_URL="https://github.com/sunnyhmz7010/ServerHarbor.git"
TMP_ROOT="${TMPDIR:-/tmp}"
WORK_DIR="$(mktemp -d "${TMP_ROOT%/}/serverharbor-run-XXXXXX")"
REPO_DIR="${WORK_DIR}/repo"
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

main() {
  require_cmd git bash

  printf 'Fetching %s from %s\n' "${PROJECT_NAME}" "${REPO_URL}"
  git clone --depth 1 "${REPO_URL}" "${REPO_DIR}" >/dev/null 2>&1
  chmod +x "${REPO_DIR}/menu.sh"
  SERVERHARBOR_HOME="${DATA_ROOT}" bash "${REPO_DIR}/menu.sh" "$@"
}

main "$@"
