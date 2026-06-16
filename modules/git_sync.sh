#!/usr/bin/env bash

set -euo pipefail

ng_git_init_repo() {
  if git -C "${NG_PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Git repository already initialized.\n'
    return 0
  fi

  git -C "${NG_PROJECT_ROOT}" init
  git -C "${NG_PROJECT_ROOT}" branch -M "${NG_GIT_BRANCH}"
  printf 'Git repository initialized on branch %s.\n' "${NG_GIT_BRANCH}"
}

ng_git_set_remote() {
  local remote_url

  printf 'Enter GitHub remote URL: '
  read -r remote_url
  [[ -n "${remote_url}" ]] || {
    printf 'Remote URL cannot be empty.\n'
    return 1
  }

  if git -C "${NG_PROJECT_ROOT}" remote get-url "${NG_GIT_REMOTE}" >/dev/null 2>&1; then
    git -C "${NG_PROJECT_ROOT}" remote set-url "${NG_GIT_REMOTE}" "${remote_url}"
  else
    git -C "${NG_PROJECT_ROOT}" remote add "${NG_GIT_REMOTE}" "${remote_url}"
  fi

  printf 'Remote %s set to %s\n' "${NG_GIT_REMOTE}" "${remote_url}"
}

ng_git_commit_state() {
  local message="${1:-auto sync $(date '+%F %T')}"

  git -C "${NG_PROJECT_ROOT}" add .
  if git -C "${NG_PROJECT_ROOT}" diff --cached --quiet; then
    printf 'No changes to commit.\n'
    return 0
  fi

  git -C "${NG_PROJECT_ROOT}" commit -m "${message}"
}

ng_git_push_remote() {
  if ! git -C "${NG_PROJECT_ROOT}" remote get-url "${NG_GIT_REMOTE}" >/dev/null 2>&1; then
    printf 'Remote %s is not configured.\n' "${NG_GIT_REMOTE}"
    return 1
  fi
  git -C "${NG_PROJECT_ROOT}" push -u "${NG_GIT_REMOTE}" "${NG_GIT_BRANCH}"
}

ng_git_sync_all() {
  ng_git_init_repo
  ng_git_commit_state "ServerHarbor sync $(date '+%F %T')"
  ng_git_push_remote
}

ng_git_auto_sync() {
  ng_git_init_repo
  ng_git_commit_state "ServerHarbor auto sync $(date '+%F %T')" || true
  ng_git_push_remote || true
}

ng_git_sync_menu() {
  local choice commit_message

  while true; do
    ng_print_header "Git Sync"
    cat <<'EOF'
1. Initialize local git repository
2. Set GitHub remote URL
3. Commit current project state
4. Push to remote
5. Commit and push all
0. Back
EOF
    printf 'Select: '
    read -r choice

    case "${choice}" in
      1) ng_git_init_repo ;;
      2) ng_git_set_remote ;;
      3)
        printf 'Commit message: '
        read -r commit_message
        ng_git_commit_state "${commit_message:-manual sync $(date '+%F %T')}"
        ;;
      4) ng_git_push_remote ;;
      5) ng_git_sync_all ;;
      0) break ;;
      *) printf 'Invalid option.\n' ;;
    esac
  done
}
