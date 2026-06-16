#!/usr/bin/env bash

set -euo pipefail

ng_git_init_repo() {
  if git -C "${NG_PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'Git repository already initialized.\n'; else printf 'Git 仓库已经初始化。\n'; fi
    return 0
  fi

  git -C "${NG_PROJECT_ROOT}" init
  git -C "${NG_PROJECT_ROOT}" branch -M "${NG_GIT_BRANCH}"
  if [[ "${NG_LANG}" == "en" ]]; then printf 'Git repository initialized on branch %s.\n' "${NG_GIT_BRANCH}"; else printf 'Git 仓库已初始化，当前分支：%s\n' "${NG_GIT_BRANCH}"; fi
}

ng_git_set_remote() {
  local remote_url

  if [[ "${NG_LANG}" == "en" ]]; then printf 'Enter GitHub remote URL: '; else printf '请输入 GitHub 远端地址：'; fi
  ng_read_line remote_url || return 130
  [[ -n "${remote_url}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then printf 'Remote URL cannot be empty.\n'; else printf '远端地址不能为空。\n'; fi
    return 1
  }

  if git -C "${NG_PROJECT_ROOT}" remote get-url "${NG_GIT_REMOTE}" >/dev/null 2>&1; then
    git -C "${NG_PROJECT_ROOT}" remote set-url "${NG_GIT_REMOTE}" "${remote_url}"
  else
    git -C "${NG_PROJECT_ROOT}" remote add "${NG_GIT_REMOTE}" "${remote_url}"
  fi

  if [[ "${NG_LANG}" == "en" ]]; then printf 'Remote %s set to %s\n' "${NG_GIT_REMOTE}" "${remote_url}"; else printf '远端 %s 已设置为 %s\n' "${NG_GIT_REMOTE}" "${remote_url}"; fi
}

ng_git_commit_state() {
  local message="${1:-auto sync $(date '+%F %T')}"

  git -C "${NG_PROJECT_ROOT}" add .
  if git -C "${NG_PROJECT_ROOT}" diff --cached --quiet; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No changes to commit.\n'; else printf '没有可提交的变更。\n'; fi
    return 0
  fi

  git -C "${NG_PROJECT_ROOT}" commit -m "${message}"
}

ng_git_push_remote() {
  if ! git -C "${NG_PROJECT_ROOT}" remote get-url "${NG_GIT_REMOTE}" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'Remote %s is not configured.\n' "${NG_GIT_REMOTE}"; else printf '远端 %s 尚未配置。\n' "${NG_GIT_REMOTE}"; fi
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
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "Git Sync"
      cat <<'EOF'
1. Initialize local git repository
2. Set GitHub remote URL
3. Commit current project state
4. Push to remote
5. Commit and push all
0. Back
EOF
    else
      ng_print_header "Git 同步"
      cat <<'EOF'
1. 初始化本地 Git 仓库
2. 设置 GitHub 远端地址
3. 提交当前项目状态
4. 推送到远端
5. 提交并推送全部变更
0. 返回
EOF
    fi
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_git_init_repo ;;
      2) ng_git_set_remote ;;
      3)
        if [[ "${NG_LANG}" == "en" ]]; then printf 'Commit message: '; else printf '请输入提交说明：'; fi
        ng_read_line commit_message || return 130
        ng_git_commit_state "${commit_message:-manual sync $(date '+%F %T')}"
        ;;
      4) ng_git_push_remote ;;
      5) ng_git_sync_all ;;
      0) break ;;
      *) ng_t invalid_option ;;
    esac
  done
}
