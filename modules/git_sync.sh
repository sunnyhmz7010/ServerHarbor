#!/usr/bin/env bash

set -euo pipefail

ng_git_init_repo() {
  if git -C "${NG_PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Git repository already initialized.\n'
    else
      printf 'Git 仓库已经初始化。\n'
    fi
    return 0
  fi

  git -C "${NG_PROJECT_ROOT}" init
  git -C "${NG_PROJECT_ROOT}" branch -M "${NG_GIT_BRANCH}"
  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Git repository initialized on branch %s.\n' "${NG_GIT_BRANCH}"
  else
    printf 'Git 仓库已初始化，当前分支：%s\n' "${NG_GIT_BRANCH}"
  fi
}

ng_git_set_remote() {
  local remote_url

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Enter GitHub remote URL: '
  else
    printf '请输入 GitHub 远端地址：'
  fi
  ng_read_line remote_url || return 130

  [[ -n "${remote_url}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Remote URL cannot be empty.\n'
    else
      printf '远端地址不能为空。\n'
    fi
    return 1
  }

  if git -C "${NG_PROJECT_ROOT}" remote get-url "${NG_GIT_REMOTE}" >/dev/null 2>&1; then
    git -C "${NG_PROJECT_ROOT}" remote set-url "${NG_GIT_REMOTE}" "${remote_url}"
  else
    git -C "${NG_PROJECT_ROOT}" remote add "${NG_GIT_REMOTE}" "${remote_url}"
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Remote %s set to %s\n' "${NG_GIT_REMOTE}" "${remote_url}"
  else
    printf '远端 %s 已设置为 %s\n' "${NG_GIT_REMOTE}" "${remote_url}"
  fi
}

ng_git_commit_state() {
  local message="${1:-auto sync $(date '+%F %T')}"

  git -C "${NG_PROJECT_ROOT}" add .
  if git -C "${NG_PROJECT_ROOT}" diff --cached --quiet; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No changes to commit.\n'
    else
      printf '没有可提交的变更。\n'
    fi
    return 0
  fi

  git -C "${NG_PROJECT_ROOT}" commit -m "${message}"
}

ng_git_push_remote() {
  if ! git -C "${NG_PROJECT_ROOT}" remote get-url "${NG_GIT_REMOTE}" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Remote %s is not configured.\n' "${NG_GIT_REMOTE}"
    else
      printf '远端 %s 尚未配置。\n' "${NG_GIT_REMOTE}"
    fi
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
      ng_print_title_box "🌿 Git Sync" "Repository snapshot and remote synchronization"
      ng_print_option "1" "🧱" "Initialize local git repository" "Create a repository and switch to the configured branch"
      ng_print_option "2" "🔗" "Set GitHub remote URL" "Configure or replace the remote named ${NG_GIT_REMOTE}"
      ng_print_option "3" "📝" "Commit current project state" "Stage all tracked and untracked changes"
      ng_print_option "4" "🚚" "Push to remote" "Push the configured branch to GitHub"
      ng_print_option "5" "⚡" "Commit and push all" "Stage, commit and push in one step"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🌿 Git 同步" "仓库快照与远端同步管理"
      ng_print_option "1" "🧱" "初始化本地 Git 仓库" "创建仓库并切换到配置的分支"
      ng_print_option "2" "🔗" "设置 GitHub 远端地址" "配置或替换名为 ${NG_GIT_REMOTE} 的远端"
      ng_print_option "3" "📝" "提交当前项目状态" "暂存当前全部已跟踪和未跟踪变更"
      ng_print_option "4" "🚚" "推送到远端" "将当前分支推送到 GitHub"
      ng_print_option "5" "⚡" "一键提交并推送" "一次完成暂存、提交和推送"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_git_init_repo ;;
      2) ng_git_set_remote ;;
      3)
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Commit message: '
        else
          printf '请输入提交说明：'
        fi
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
