#!/usr/bin/env bash

set -euo pipefail

ng_scan_auth_failures() {
  local auth_log=""

  if [[ -f /var/log/auth.log ]]; then
    auth_log="/var/log/auth.log"
  elif [[ -f /var/log/secure ]]; then
    auth_log="/var/log/secure"
  fi

  local summary=""
  local total=0
  if [[ -n "${auth_log}" ]]; then
    summary="$(grep -Ei 'Failed password|authentication failure' "${auth_log}" 2>/dev/null \
      | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
      | sort | uniq -c | sort -nr | head -10 || true)"
    total="$(grep -ciE 'Failed password|authentication failure' "${auth_log}" 2>/dev/null || echo 0)"
    total=$(echo "${total}" | tr -d '[:space:]')
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🔍 Failed Login Statistics"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "Auth Log"
  else
    ng_report_header "🔍 失败登录统计"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "认证日志"
  fi

  if [[ -z "${auth_log}" ]]; then
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Log file" || echo "日志文件")" "$( [[ "${NG_LANG}" == "en" ]] && echo "Not found" || echo "未找到" )"
  else
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Log file" || echo "日志文件")" "${auth_log}"
    ng_report_separator
    if [[ -n "${summary}" ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "  Top source IPs:"
      else
        printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "  来源 IP TOP10:"
      fi
      printf '%s\n' "${summary}" | while IFS= read -r line; do
        printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
      done
    else
      ng_report_line "  $( [[ "${NG_LANG}" == "en" ]] && echo "No failed login entries found." || echo "未发现失败登录记录。" )"
    fi
  fi

  ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Total failures:" || echo "失败总数:")" "${total}"
  if [[ "${total}" -gt 0 ]]; then
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_WARN}" "⚠️  $( [[ "${NG_LANG}" == "en" ]] && echo "Abnormal logins detected" || echo "存在异常登录" )")"
    ng_report_advice_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Suggestions" || echo "建议" )"
    printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "• Install fail2ban to block brute force attacks" || echo "• 安装 fail2ban 防暴力破解" )"
    printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "• Configure IP whitelist or SSH key-only auth" || echo "• 配置 IP 白名单或仅密钥认证" )"
  else
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_OK}" "✅ $( [[ "${NG_LANG}" == "en" ]] && echo "Normal" || echo "正常" )")"
  fi
  ng_report_footer
}

ng_scan_web_attacks() {
  local access_log="/var/log/nginx/access.log"
  local summary=""
  local total=0

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🌐 Suspicious Web Request Scan"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "Access Log"
  else
    ng_report_header "🌐 可疑 Web 请求扫描"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "访问日志"
  fi

  if [[ ! -f "${access_log}" ]]; then
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Log file" || echo "日志文件")" "$( [[ "${NG_LANG}" == "en" ]] && echo "Not found (nginx not installed)" || echo "未找到（nginx 未安装）" )"
  else
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Log file" || echo "日志文件")" "${access_log}"
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Patterns" || echo "检测模式")" "wp-admin, phpmyadmin, .env, SQL injection, path traversal"
    ng_report_separator

    summary="$(grep -Ei 'wp-admin|phpmyadmin|\.env|select.+from|union.+select|/etc/passwd|\.\./' "${access_log}" 2>/dev/null \
      | awk '{print $1}' | sort | uniq -c | sort -nr | head -10 || true)"
    total="$(grep -ciE 'wp-admin|phpmyadmin|\.env|select.+from|union.+select|/etc/passwd|\.\./' "${access_log}" 2>/dev/null || echo 0)"
    total=$(echo "${total}" | tr -d '[:space:]')

    if [[ -n "${summary}" ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "  Top source IPs:"
      else
        printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "  来源 IP TOP10:"
      fi
      printf '%s\n' "${summary}" | while IFS= read -r line; do
        printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
      done
    else
      ng_report_line "  $( [[ "${NG_LANG}" == "en" ]] && echo "No suspicious request patterns found." || echo "未发现可疑请求特征。" )"
    fi
  fi

  ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Suspicious requests:" || echo "可疑请求:")" "${total}"
  if [[ "${total}" -gt 0 ]]; then
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_WARN}" "⚠️  $( [[ "${NG_LANG}" == "en" ]] && echo "Scanning activity detected" || echo "存在扫描行为" )")"
    ng_report_advice_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Suggestions" || echo "建议" )"
    printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "• Configure WAF or nginx deny rules" || echo "• 配置 WAF 或 nginx 的 deny 规则" )"
    printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "• Block offending IPs at firewall level" || echo "• 在防火墙层面封禁攻击 IP" )"
  else
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_OK}" "✅ $( [[ "${NG_LANG}" == "en" ]] && echo "Normal" || echo "正常" )")"
  fi
  ng_report_footer
}

ng_firewall_summary() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🔥 Firewall Status"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "Firewall Info"
  else
    ng_report_header "🔥 防火墙状态"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "防火墙信息"
  fi

  local backend="none"
  local status="inactive"
  local rule_count=0

  if command -v ufw >/dev/null 2>&1; then
    backend="ufw"
    local ufw_output
    ufw_output="$(ufw status verbose 2>/dev/null || true)"
    if [[ "${ufw_output}" == *"Status: active"* ]]; then
      status="active"
    fi
    rule_count="$(echo "${ufw_output}" | grep -c "^[0-9]" 2>/dev/null || echo 0)"
    rule_count=$(echo "${rule_count}" | tr -d '[:space:]')
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Backend" || echo "后端")" "ufw"
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Status" || echo "状态")" "${status}"
    ng_report_separator
    printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "  ${ufw_output}" | while IFS= read -r line; do
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
    done
  elif command -v firewall-cmd >/dev/null 2>&1; then
    backend="firewalld"
    local fwd_output
    fwd_output="$(firewall-cmd --list-all 2>/dev/null || true)"
    status="active"
    rule_count="$(echo "${fwd_output}" | grep -c "services\|ports" 2>/dev/null || echo 0)"
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Backend" || echo "后端")" "firewalld"
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Status" || echo "状态")" "${status}"
    ng_report_separator
    printf '%s\n' "${fwd_output}" | while IFS= read -r line; do
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
    done
  elif command -v iptables >/dev/null 2>&1; then
    backend="iptables"
    local ipt_output
    ipt_output="$(iptables -L -n --line-numbers 2>/dev/null | head -30 || true)"
    rule_count="$(iptables -L -n 2>/dev/null | grep -c "^[0-9]" 2>/dev/null || echo 0)"
    rule_count=$(echo "${rule_count}" | tr -d '[:space:]')
    if [[ "${rule_count}" -gt 0 ]]; then
      status="active"
    fi
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Backend" || echo "后端")" "iptables"
    ng_report_separator
    printf '%s\n' "${ipt_output}" | while IFS= read -r line; do
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
    done
  else
    ng_report_line "  $( [[ "${NG_LANG}" == "en" ]] && echo "No firewall tool found." || echo "未找到防火墙工具。" )"
  fi

  ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Backend:" || echo "后端:")" "${backend}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Rules:" || echo "规则数:")" "${rule_count}"
  if [[ "${status}" == "active" ]]; then
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_OK}" "✅ $( [[ "${NG_LANG}" == "en" ]] && echo "Firewall enabled" || echo "防火墙已启用" )")"
  else
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_WARN}" "⚠️  $( [[ "${NG_LANG}" == "en" ]] && echo "Firewall not active or not found" || echo "防火墙未启用或未找到" )")"
  fi
  ng_report_footer
}

ng_select_baseline() {
  local mode="${1:-single}"
  local baseline_count=0
  local -a baseline_names=()
  local -a baseline_files=()

  for f in "${NG_STATE_DIR}"/integrity-*.sha256; do
    [[ -f "${f}" ]] || continue
    local bname="${f##*/integrity-}"
    bname="${bname%.sha256}"
    baseline_names+=("${bname}")
    baseline_files+=("${f}")
    ((baseline_count++)) || true
  done

  if [[ "${baseline_count}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No baselines found. Create one first.\n' >&2
    else
      printf '未找到基线，请先创建。\n' >&2
    fi
    return 1
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nExisting baselines:\n' >&2
  else
    printf '\n已有基线：\n' >&2
  fi

  local idx=1
  for f in "${NG_STATE_DIR}"/integrity-*.sha256; do
    [[ -f "${f}" ]] || continue
    local bname="${f##*/integrity-}"
    bname="${bname%.sha256}"
    local file_count
    file_count=$(wc -l < "${f}" 2>/dev/null | tr -d ' ')
    local mtime
    mtime=$(date -r "${f}" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "${f}" 2>/dev/null | cut -d. -f1 || echo "?")
    printf '  [%d] %-20s %5s files   %s\n' "${idx}" "${bname}" "${file_count}" "${mtime}" >&2
    ((idx++)) || true
  done

  if [[ "${mode}" == "all" ]]; then
    printf '  [a] %s\n' "$( [[ "${NG_LANG}" == "en" ]] && echo "Verify all" || echo "全部校验" )" >&2
  fi

  printf '\n' >&2
  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Select baseline (number): ' >&2
  else
    printf '选择基线（输入编号）：' >&2
  fi

  local selection
  read -r selection < /dev/tty

  if [[ "${selection}" == "a" ]] && [[ "${mode}" == "all" ]]; then
    printf '%s\n' "all"
    return 0
  fi

  if [[ "${selection}" =~ ^[0-9]+$ ]] && [[ "${selection}" -ge 1 ]] && [[ "${selection}" -le "${baseline_count}" ]]; then
    local sel_idx=$((selection - 1))
    printf '%s\n' "${baseline_files[${sel_idx}]}"
    return 0
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Invalid selection.\n' >&2
  else
    printf '无效选择。\n' >&2
  fi
  return 1
}

ng_integrity_create_baseline() {
  if [[ -z "${NG_WATCH_PATHS:-}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No watch paths configured. Set NG_WATCH_PATHS in serverharbor.conf.\n'
    else
      printf '未配置监控路径，请在 serverharbor.conf 中设置 NG_WATCH_PATHS。\n'
    fi
    return 1
  fi

  local baseline_name="default"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🧬 Create Integrity Baseline"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "Existing Baselines"
  else
    ng_report_header "🧬 创建完整性基线"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "已有基线"
  fi

  local has_existing=0
  for f in "${NG_STATE_DIR}"/integrity-*.sha256; do
    [[ -f "${f}" ]] || continue
    local bname="${f##*/integrity-}"
    bname="${bname%.sha256}"
    local file_count
    file_count=$(wc -l < "${f}" 2>/dev/null | tr -d ' ')
    local mtime
    mtime=$(date -r "${f}" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "${f}" 2>/dev/null | cut -d. -f1 || echo "?")
    printf '%s   %-20s %5s files   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${bname}" "${file_count}" "${mtime}"
    has_existing=1
  done

  if [[ "${has_existing}" -eq 0 ]]; then
    printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "(None)" || echo "（无）" )"
  fi

  ng_report_separator
  ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Watch paths" || echo "监控路径")" "${NG_WATCH_PATHS}"

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\n  Enter baseline name (Enter to overwrite "default"): '
  else
    printf '\n  输入基线名称（回车覆盖 "default"）：'
  fi
  ng_read_line baseline_name || return 130
  baseline_name="${baseline_name:-default}"

  local baseline_file
  baseline_file="$(ng_get_baseline_file "${baseline_name}")"

  if [[ -f "${baseline_file}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '  Baseline "%s" already exists. Overwrite? [y/N]: ' "${baseline_name}"
    else
      printf '  基线 "%s" 已存在，是否覆盖？[y/N]：' "${baseline_name}"
    fi
    local confirm
    ng_read_line confirm || return 130
    if [[ ! "${confirm}" =~ ^[Yy] ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Cancelled.\n'
      else
        printf '已取消。\n'
      fi
      return 0
    fi
  fi

  ng_report_separator

  local tmp_baseline="${baseline_file}.tmp"
  : > "${tmp_baseline}"
  local total_files=0
  local skipped_paths=0

  for watch_path in ${NG_WATCH_PATHS}; do
    if [[ -e "${watch_path}" ]]; then
      if [[ -r "${watch_path}" ]]; then
        local file_count
        file_count=$(find "${watch_path}" -type f 2>/dev/null | wc -l)
        find "${watch_path}" -type f -exec sha256sum {} \; >> "${tmp_baseline}" 2>/dev/null || true
        printf '%s   ✓ %s' "$(ng_color "${NG_C_PANEL}" "║")" "${watch_path}"
        if [[ "${NG_LANG}" == "en" ]]; then
          printf '  (%d files)\n' "${file_count}"
        else
          printf '（%d 个文件）\n' "${file_count}"
        fi
        total_files=$((total_files + file_count))
      else
        printf '%s   ✗ %s' "$(ng_color "${NG_C_PANEL}" "║")" "${watch_path}"
        if [[ "${NG_LANG}" == "en" ]]; then
          printf '  (not readable)\n'
        else
          printf '（不可读）\n'
        fi
        ((skipped_paths++)) || true
      fi
    else
      printf '%s   ✗ %s' "$(ng_color "${NG_C_PANEL}" "║")" "${watch_path}"
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '  (not found)\n'
      else
        printf '（不存在）\n'
      fi
      ((skipped_paths++)) || true
    fi
  done

  mv -f "${tmp_baseline}" "${baseline_file}" 2>/dev/null || true

  ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Baseline name:" || echo "基线名称:")" "${baseline_name}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Indexed files:" || echo "索引文件:")" "${total_files}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Skipped paths:" || echo "跳过路径:")" "${skipped_paths}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_OK}" "✅ $( [[ "${NG_LANG}" == "en" ]] && echo "Baseline created" || echo "基线已建立" )")"
  ng_report_footer

  ng_log "INFO" "Integrity baseline '${baseline_name}' created: ${total_files} files indexed"
}

ng_integrity_verify() {
  local baseline_file
  baseline_file="$(ng_select_baseline all)" || return 1

  if [[ "${baseline_file}" == "all" ]]; then
    for f in "${NG_STATE_DIR}"/integrity-*.sha256; do
      [[ -f "${f}" ]] || continue
      local bname="${f##*/integrity-}"
      bname="${bname%.sha256}"
      ng_integrity_verify_single "${f}" "${bname}"
      printf '\n'
    done
    return 0
  fi

  local bname="${baseline_file##*/integrity-}"
  bname="${bname%.sha256}"
  ng_integrity_verify_single "${baseline_file}" "${bname}"
}

ng_integrity_verify_single() {
  local baseline_file="$1"
  local baseline_name="$2"

  local changes=0
  local total=0
  local passed=0
  local -a changed_files=()

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "✅ Integrity Verification"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "Baseline"
  else
    ng_report_header "✅ 完整性校验"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "基线"
  fi

  ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Name" || echo "名称")" "${baseline_name}"
  ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "File" || echo "文件")" "${baseline_file}"
  ng_report_separator

  while IFS= read -r line; do
    if [[ "${line}" == *"FAILED"* ]]; then
      printf '%s   %s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_ERR}" "✗")" "${line}"
      local failed_file
      failed_file=$(echo "${line}" | awk -F: '{print $1}' | sed 's/^ *//')
      changed_files+=("${failed_file}")
      ((changes++)) || true
      ((total++)) || true
    elif [[ "${line}" == *"OK"* ]]; then
      printf '%s   %s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_OK}" "✓")" "${line}"
      ((passed++)) || true
      ((total++)) || true
    else
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
    fi
  done < <(cd / && sha256sum -c "${baseline_file}" 2>&1 || true)

  ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Baseline:" || echo "基线:")" "${baseline_name}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Checked files:" || echo "检查文件:")" "${total}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Passed:" || echo "通过:")" "${passed}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Changed:" || echo "变更:")" "${changes}"

  if [[ "${changes}" -gt 0 ]]; then
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_WARN}" "⚠️  $( [[ "${NG_LANG}" == "en" ]] && echo "Files have changed since baseline" || echo "有文件自基线以来发生了变化" )")"
    ng_report_separator
    printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_ERR}" "  $( [[ "${NG_LANG}" == "en" ]] && echo "Changed files:" || echo "变更文件：" )")"
    for cf in "${changed_files[@]}"; do
      printf '%s   ✗ %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${cf}"
    done
  else
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_OK}" "✅ $( [[ "${NG_LANG}" == "en" ]] && echo "All files match baseline" || echo "所有文件与基线一致" )")"
  fi
  ng_report_footer
}

ng_manage_watch_paths() {
  local choice

  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "📂 Integrity Watch Paths" "Manage paths for file integrity monitoring"
      printf '\nCurrent watch paths:\n'
    else
      ng_print_title_box "📂 完整性监控路径" "管理文件完整性监控的路径"
      printf '\n当前监控路径：\n'
    fi

    local -a paths_array=()
    if [[ -n "${NG_WATCH_PATHS:-}" ]]; then
      local line_num=1
      for path in ${NG_WATCH_PATHS}; do
        printf '  [%d] %s\n' "${line_num}" "${path}"
        paths_array+=("${path}")
        ((line_num++)) || true
      done
    else
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '  (No paths configured)\n'
      else
        printf '  （未配置路径）\n'
      fi
    fi

    printf '\n'
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '  [1] Add path(s)\n'
      printf '  [2] Remove path(s)\n'
      printf '  [3] Reset to defaults\n'
      printf '  [0] Back\n'
    else
      printf '  [1] 添加路径\n'
      printf '  [2] 删除路径\n'
      printf '  [3] 恢复默认\n'
      printf '  [0] 返回\n'
    fi

    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1)
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter path(s) to monitor (space-separated, e.g. /etc /opt /var/www): '
        else
          printf '输入要监控的路径（空格分隔，如 /etc /opt /var/www）：'
        fi
        local new_paths
        ng_read_line new_paths || return 130

        if [[ -n "${new_paths}" ]]; then
          local added=0
          local skipped=0
          for np in ${new_paths}; do
            if [[ -e "${np}" ]]; then
              if [[ " ${NG_WATCH_PATHS} " != *" ${np} "* ]]; then
                NG_WATCH_PATHS="${NG_WATCH_PATHS} ${np}"
                ((added++)) || true
                printf '  ✓ %s\n' "${np}"
              else
                if [[ "${NG_LANG}" == "en" ]]; then
                  printf '  ⚠ %s (already exists)\n' "${np}"
                else
                  printf '  ⚠ %s（已存在）\n' "${np}"
                fi
                ((skipped++)) || true
              fi
            else
              if [[ "${NG_LANG}" == "en" ]]; then
                printf '  ✗ %s (not found)\n' "${np}"
              else
                printf '  ✗ %s（不存在）\n' "${np}"
              fi
              ((skipped++)) || true
            fi
          done

          NG_WATCH_PATHS=$(echo "${NG_WATCH_PATHS}" | sed 's/^ *//')
          if grep -q '^NG_WATCH_PATHS=' "${NG_CONFIG_FILE}" 2>/dev/null; then
            awk -v val="NG_WATCH_PATHS=\"${NG_WATCH_PATHS}\"" '/^NG_WATCH_PATHS=/{print val;next}{print}' "${NG_CONFIG_FILE}" > "${NG_CONFIG_FILE}.tmp" && mv -f "${NG_CONFIG_FILE}.tmp" "${NG_CONFIG_FILE}"
          else
            echo "NG_WATCH_PATHS=\"${NG_WATCH_PATHS}\"" >> "${NG_CONFIG_FILE}"
          fi

          if [[ "${NG_LANG}" == "en" ]]; then
            printf '\nAdded: %d, Skipped: %d\n' "${added}" "${skipped}"
          else
            printf '\n添加: %d, 跳过: %d\n' "${added}" "${skipped}"
          fi
        fi
        ;;
      2)
        if [[ "${#paths_array[@]}" -eq 0 ]]; then
          if [[ "${NG_LANG}" == "en" ]]; then
            printf 'No paths to remove.\n'
          else
            printf '没有可删除的路径。\n'
          fi
        else
          if [[ "${NG_LANG}" == "en" ]]; then
            printf 'Enter path numbers to remove (comma-separated, e.g. 1,3 or a for all): '
          else
            printf '输入要删除的编号（逗号分隔，如 1,3 或 a 全部删除）：'
          fi
          local remove_input
          ng_read_line remove_input || return 130

          if [[ -n "${remove_input}" ]]; then
            local -a to_remove=()

            if [[ "${remove_input}" == "a" ]] || [[ "${remove_input}" == "A" ]]; then
              for ((i=0; i<${#paths_array[@]}; i++)); do
                to_remove+=("${paths_array[$i]}")
              done
            else
              IFS=',' read -ra remove_nums <<< "${remove_input}"
              for num in "${remove_nums[@]}"; do
                num=$(echo "${num}" | tr -d ' ')
                if [[ "${num}" =~ ^[0-9]+$ ]] && [[ "${num}" -ge 1 ]] && [[ "${num}" -le "${#paths_array[@]}" ]]; then
                  to_remove+=("${paths_array[$((num-1))]}")
                fi
              done
            fi

            if [[ "${#to_remove[@]}" -gt 0 ]]; then
              for rp in "${to_remove[@]}"; do
                NG_WATCH_PATHS=$(echo " ${NG_WATCH_PATHS} " | sed "s| ${rp} | |g" | sed 's/^ *//;s/ *$//')
                printf '  ✓ %s\n' "${rp}"
              done

              if grep -q '^NG_WATCH_PATHS=' "${NG_CONFIG_FILE}" 2>/dev/null; then
                awk -v val="NG_WATCH_PATHS=\"${NG_WATCH_PATHS}\"" '/^NG_WATCH_PATHS=/{print val;next}{print}' "${NG_CONFIG_FILE}" > "${NG_CONFIG_FILE}.tmp" && mv -f "${NG_CONFIG_FILE}.tmp" "${NG_CONFIG_FILE}"
              fi

              if [[ "${NG_LANG}" == "en" ]]; then
                printf '\nRemoved %d path(s).\n' "${#to_remove[@]}"
              else
                printf '\n已删除 %d 个路径。\n' "${#to_remove[@]}"
              fi
            fi
          fi
        fi
        ;;
      3)
        NG_WATCH_PATHS="/etc /var/www /root"
        if grep -q '^NG_WATCH_PATHS=' "${NG_CONFIG_FILE}" 2>/dev/null; then
          sed -i "s#^NG_WATCH_PATHS=.*#NG_WATCH_PATHS=\"${NG_WATCH_PATHS}\"#" "${NG_CONFIG_FILE}"
        else
          echo "NG_WATCH_PATHS=\"${NG_WATCH_PATHS}\"" >> "${NG_CONFIG_FILE}"
        fi
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Reset to default paths.\n'
        else
          printf '已恢复默认路径。\n'
        fi
        ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || return 130
  done
}

ng_security_score() {
  local score=100
  local issues=()

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "📊 Security Score"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Checks Performed" || echo "执行检查" )"
  else
    ng_report_header "📊 安全评分"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "执行检查"
  fi

  printf '%s   ✓ %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "SSH configuration" || echo "SSH 配置" )"
  printf '%s   ✓ %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "Firewall status" || echo "防火墙状态" )"
  printf '%s   ✓ %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "Auth log analysis" || echo "认证日志分析" )"

  if [[ "${EUID}" -eq 0 ]]; then
    score=$((score - 10))
    if [[ "${NG_LANG}" == "en" ]]; then
      issues+=("Running as root (-10)")
    else
      issues+=("以 root 身份运行 (-10)")
    fi
  fi

  if ! grep -qE '^[^#]*PasswordAuthentication no' /etc/ssh/sshd_config 2>/dev/null; then
    score=$((score - 15))
    if [[ "${NG_LANG}" == "en" ]]; then
      issues+=("SSH password authentication enabled (-15)")
    else
      issues+=("SSH 密码认证已启用 (-15)")
    fi
  fi

  if grep -qE '^[^#]*PermitRootLogin yes' /etc/ssh/sshd_config 2>/dev/null; then
    score=$((score - 20))
    if [[ "${NG_LANG}" == "en" ]]; then
      issues+=("Root login permitted (-20)")
    else
      issues+=("允许 root 登录 (-20)")
    fi
  fi

  if ! command -v ufw >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1 && ! command -v iptables >/dev/null 2>&1; then
    score=$((score - 25))
    if [[ "${NG_LANG}" == "en" ]]; then
      issues+=("No firewall detected (-25)")
    else
      issues+=("未检测到防火墙 (-25)")
    fi
  fi

  local auth_log=""
  [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
  [[ -f /var/log/secure ]] && auth_log="/var/log/secure"

  if [[ -n "${auth_log}" ]]; then
    local failed_count
    failed_count=$(grep -c "Failed password" "${auth_log}" 2>/dev/null || true)
    failed_count="${failed_count:-0}"
    failed_count=$(echo "${failed_count}" | tr -d '[:space:]')
    if [[ "${failed_count}" -gt 100 ]]; then
      score=$((score - 10))
      if [[ "${NG_LANG}" == "en" ]]; then
        issues+=("High number of failed login attempts: ${failed_count} (-10)")
      else
        issues+=("大量失败登录尝试: ${failed_count} 次 (-10)")
      fi
    fi
  fi

  if [[ "${score}" -lt 0 ]]; then
    score=0
  fi

  local risk_level risk_color
  if [[ "${score}" -ge 90 ]]; then
    risk_level="$( [[ "${NG_LANG}" == "en" ]] && echo "Low" || echo "低" )"
    risk_color="${NG_C_OK}"
  elif [[ "${score}" -ge 70 ]]; then
    risk_level="$( [[ "${NG_LANG}" == "en" ]] && echo "Medium" || echo "中等" )"
    risk_color="${NG_C_WARN}"
  elif [[ "${score}" -ge 50 ]]; then
    risk_level="$( [[ "${NG_LANG}" == "en" ]] && echo "High" || echo "高" )"
    risk_color="${NG_C_ERR}"
  else
    risk_level="$( [[ "${NG_LANG}" == "en" ]] && echo "Critical" || echo "严重" )"
    risk_color="${NG_C_ERR}"
  fi

  ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Score" || echo "评分" )"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Score:" || echo "评分:")" "${score}/100"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Risk level:" || echo "风险等级:")" "$(ng_color "${risk_color}" "${risk_level}")"

  if [[ "${#issues[@]}" -gt 0 ]]; then
    ng_report_separator
    printf '%s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$(ng_color "${NG_C_WARN}" "  $( [[ "${NG_LANG}" == "en" ]] && echo "Issues found:" || echo "发现问题：" )")"
    for issue in "${issues[@]}"; do
      printf '%s   • %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${issue}"
    done

    ng_report_advice_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Suggestions" || echo "建议" )"
    if grep -qE '^[^#]*PasswordAuthentication yes' /etc/ssh/sshd_config 2>/dev/null; then
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "• Disable password auth, use SSH keys" || echo "• 禁用密码认证，使用密钥登录" )"
    fi
    if grep -qE '^[^#]*PermitRootLogin yes' /etc/ssh/sshd_config 2>/dev/null; then
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "• Disable root login (PermitRootLogin no)" || echo "• 禁用 root 直接登录 (PermitRootLogin no)" )"
    fi
    if [[ -n "${auth_log}" ]]; then
      local fc
      fc=$(grep -c "Failed password" "${auth_log}" 2>/dev/null || true)
      fc="${fc:-0}"
      fc=$(echo "${fc}" | tr -d '[:space:]')
      if [[ "${fc}" -gt 50 ]]; then
        printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "• Install fail2ban to block brute force" || echo "• 安装 fail2ban 防暴力破解" )"
      fi
    fi
    if ! command -v ufw >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1 && ! command -v iptables >/dev/null 2>&1; then
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "• Enable a firewall (ufw recommended)" || echo "• 启用防火墙（推荐 ufw）" )"
    fi
    printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "$( [[ "${NG_LANG}" == "en" ]] && echo "• Run security reports regularly" || echo "• 定期运行安全报告" )"
  else
    ng_report_line "  $( [[ "${NG_LANG}" == "en" ]] && echo "No major security issues found." || echo "未发现重大安全问题。" )"
  fi
  ng_report_footer
}

ng_security_report() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🛡 ServerHarbor Security Report"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
  else
    ng_report_header "🛡 ServerHarbor 安全巡检报告"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
  fi

  local auth_log=""
  [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
  [[ -f /var/log/secure ]] && auth_log="/var/log/secure"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section_start "Failed Login Sources"
  else
    ng_report_section_start "失败登录来源"
  fi
  if [[ -n "${auth_log}" ]]; then
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Auth Log" || echo "日志文件")" "${auth_log}"
    local login_total
    login_total=$(grep -ciE 'Failed password|authentication failure' "${auth_log}" 2>/dev/null || echo 0)
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Total failures" || echo "失败总数")" "${login_total}"
    local login_output
    login_output="$(grep -Ei 'Failed password' "${auth_log}" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -nr | head -5)" || true
    if [[ -n "${login_output}" ]]; then
      printf '%s\n' "${login_output}" | while IFS= read -r line; do
        printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
      done
    fi
  else
    ng_report_line "  $( [[ "${NG_LANG}" == "en" ]] && echo "No auth log found." || echo "未找到认证日志文件。" )"
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section_start "Suspicious Web Requests"
  else
    ng_report_section_start "可疑 Web 请求"
  fi
  local access_log="/var/log/nginx/access.log"
  if [[ -f "${access_log}" ]]; then
    local web_total
    web_total=$(grep -ciE 'wp-admin|phpmyadmin|\.env|select.+from|union.+select' "${access_log}" 2>/dev/null || echo 0)
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Access Log" || echo "访问日志")" "${access_log}"
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Suspicious" || echo "可疑请求")" "${web_total}"
    local web_output
    web_output="$(grep -Ei 'wp-admin|phpmyadmin|\.env|select.+from|union.+select' "${access_log}" 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -nr | head -5)" || true
    if [[ -n "${web_output}" ]]; then
      printf '%s\n' "${web_output}" | while IFS= read -r line; do
        printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
      done
    fi
  else
    ng_report_line "  $( [[ "${NG_LANG}" == "en" ]] && echo "No nginx access log found." || echo "未找到 nginx 访问日志。" )"
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section_start "Listening Ports"
  else
    ng_report_section_start "监听端口"
  fi
  local port_count
  port_count=$(ss -lntp 2>/dev/null | tail -n +2 | wc -l || echo 0)
  ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Port count" || echo "端口数")" "${port_count}"
  ss -lntp 2>/dev/null | sed -n '1,10p' | while IFS= read -r line; do
    printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
  done || true

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section_start "Firewall"
  else
    ng_report_section_start "防火墙"
  fi
  if command -v ufw >/dev/null 2>&1; then
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Backend" || echo "后端")" "ufw"
    ufw status verbose 2>/dev/null | while IFS= read -r line; do
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
    done || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Backend" || echo "后端")" "firewalld"
    firewall-cmd --list-all 2>/dev/null | while IFS= read -r line; do
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
    done || true
  elif command -v iptables >/dev/null 2>&1; then
    ng_report_detail "$([[ "${NG_LANG}" == "en" ]] && echo "Backend" || echo "后端")" "iptables"
    iptables -L -n --line-numbers 2>/dev/null | sed -n '1,10p' | while IFS= read -r line; do
      printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
    done || true
  else
    ng_report_line "  $( [[ "${NG_LANG}" == "en" ]] && echo "No firewall tool found." || echo "未找到防火墙工具。" )"
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_summary_start "Overall Summary"
  else
    ng_report_summary_start "综合摘要"
  fi

  local risk_score=100
  [[ "${EUID}" -eq 0 ]] && risk_score=$((risk_score - 10))
  ! grep -qE '^[^#]*PasswordAuthentication no' /etc/ssh/sshd_config 2>/dev/null && risk_score=$((risk_score - 15))
  grep -qE '^[^#]*PermitRootLogin yes' /etc/ssh/sshd_config 2>/dev/null && risk_score=$((risk_score - 20))
  [[ "${port_count}" -gt 10 ]] && risk_score=$((risk_score - 5))
  [[ "${risk_score}" -lt 0 ]] && risk_score=0

  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Security score:" || echo "安全评分:")" "${risk_score}/100"

  local risk_level risk_color
  if [[ "${risk_score}" -ge 90 ]]; then
    risk_level="$( [[ "${NG_LANG}" == "en" ]] && echo "Low" || echo "低" )"
    risk_color="${NG_C_OK}"
  elif [[ "${risk_score}" -ge 70 ]]; then
    risk_level="$( [[ "${NG_LANG}" == "en" ]] && echo "Medium" || echo "中等" )"
    risk_color="${NG_C_WARN}"
  else
    risk_level="$( [[ "${NG_LANG}" == "en" ]] && echo "High" || echo "高" )"
    risk_color="${NG_C_ERR}"
  fi
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Risk level:" || echo "风险等级:")" "$(ng_color "${risk_color}" "${risk_level}")"

  ng_report_footer
}

ng_security_menu() {
  local choice

  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛡 Security Guard" "Auth logs, web attacks, firewall and integrity monitoring"
      ng_print_option "1" "📄" "Run security report" "Aggregate auth failures, web probes, ports and firewall state"
      ng_print_option "2" "🔍" "Show failed login statistics" "Count recent failed login source IPs"
      ng_print_option "3" "🌐" "Show suspicious web requests" "Inspect nginx access log for common attack patterns"
      ng_print_option "4" "🔥" "Show firewall summary" "Display ufw, firewalld or iptables state"
      ng_print_option "5" "🧬" "Create integrity baseline" "Hash all files under configured watch paths"
      ng_print_option "6" "✅" "Verify integrity baseline" "Check current files against stored hashes"
      ng_print_option "7" "📂" "Manage watch paths" "Add/remove paths for integrity monitoring"
      ng_print_option "8" "📊" "Security score" "Calculate system security score"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛡 安全卫士" "认证日志、Web 攻击、防火墙与完整性监控"
      ng_print_option "1" "📄" "生成安全报告" "汇总认证失败、Web 探测、端口与防火墙状态"
      ng_print_option "2" "🔍" "查看失败登录统计" "统计近期失败登录来源 IP"
      ng_print_option "3" "🌐" "查看可疑 Web 请求" "检查 nginx 访问日志中的常见攻击特征"
      ng_print_option "4" "🔥" "查看防火墙状态" "显示 ufw、firewalld 或 iptables 状态"
      ng_print_option "5" "🧬" "生成完整性基线" "对监控路径下文件生成哈希清单"
      ng_print_option "6" "✅" "校验完整性基线" "按已有哈希清单检查当前文件"
      ng_print_option "7" "📂" "管理监控路径" "添加/删除完整性监控的路径"
      ng_print_option "8" "📊" "安全评分" "计算系统安全评分"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_security_report ;;
      2) ng_scan_auth_failures ;;
      3) ng_scan_web_attacks ;;
      4) ng_firewall_summary ;;
      5) ng_integrity_create_baseline ;;
      6) ng_integrity_verify ;;
      7) ng_manage_watch_paths ;;
      8) ng_security_score ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || return 130
  done
}
