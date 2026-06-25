#!/usr/bin/env bash

set -euo pipefail

ng_scan_auth_failures() {
  local auth_log=""
  local summary=""

  if [[ -f /var/log/auth.log ]]; then
    auth_log="/var/log/auth.log"
  elif [[ -f /var/log/secure ]]; then
    auth_log="/var/log/secure"
  fi

  if [[ -z "${auth_log}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No auth log found.\n'
    else
      printf '未找到认证日志文件。\n'
    fi
    return 0
  fi

  summary="$(
    grep -Ei 'Failed password|authentication failure' "${auth_log}" 2>/dev/null \
      | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
      | sort | uniq -c | sort -nr | head || true
  )"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section 'Failed Login Sources'
    ng_report_kv 'Auth Log' "${auth_log}"
    ng_report_note 'Top source IPs by failed password events:'
  else
    ng_report_section '失败登录来源'
    ng_report_kv '日志文件' "${auth_log}"
    ng_report_note '以下为失败密码登录事件最多的来源 IP：'
  fi

  if [[ -z "${summary}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_report_note 'No failed login entries found.'
    else
      ng_report_note '未发现失败登录记录。'
    fi
    return 0
  fi

  printf '%s\n' "${summary}"
}

ng_scan_web_attacks() {
  local access_log="/var/log/nginx/access.log"
  local summary=""

  [[ -f "${access_log}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_report_section 'Suspicious Web Requests'
      ng_report_note 'No nginx access log found.'
    else
      ng_report_section '可疑 Web 请求'
      ng_report_note '未找到 nginx 访问日志。'
    fi
    return 0
  }

  summary="$(
    grep -Ei 'wp-admin|phpmyadmin|\.env|select.+from|union.+select|/etc/passwd|\.\./' "${access_log}" \
      | awk '{print $1}' | sort | uniq -c | sort -nr | head || true
  )"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section 'Suspicious Web Requests'
    ng_report_kv 'Access Log' "${access_log}"
    ng_report_note 'Top source IPs matching common suspicious request patterns:'
  else
    ng_report_section '可疑 Web 请求'
    ng_report_kv '访问日志' "${access_log}"
    ng_report_note '以下为命中常见可疑请求特征最多的来源 IP：'
  fi

  if [[ -z "${summary}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_report_note 'No suspicious request patterns found.'
    else
      ng_report_note '未发现可疑请求特征。'
    fi
    return 0
  fi

  printf '%s\n' "${summary}"
}

ng_firewall_summary() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_section 'Firewall Summary'
    ng_report_note 'Detected firewall backend and current active rules:'
  else
    ng_report_section '防火墙状态'
    ng_report_note '以下为检测到的防火墙后端及当前生效规则：'
  fi

  if command -v ufw >/dev/null 2>&1; then
    ng_report_kv 'Backend' 'ufw'
    ufw status verbose || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    ng_report_kv 'Backend' 'firewalld'
    firewall-cmd --list-all || true
  elif command -v iptables >/dev/null 2>&1; then
    ng_report_kv 'Backend' 'iptables'
    iptables -L -n --line-numbers || true
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_report_note 'No firewall tool found.'
    else
      ng_report_note '未找到防火墙工具。'
    fi
  fi
}

ng_integrity_create_baseline() {
  local baseline_file="${NG_INTEGRITY_DB}"

  [[ -f "${NG_WATCH_FILE}" ]] || {
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Watch file is missing: %s\n' "${NG_WATCH_FILE}"
    else
      printf '监控路径配置文件不存在：%s\n' "${NG_WATCH_FILE}"
    fi
    return 1
  }

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Creating Integrity Baseline"
    printf 'Scanning paths defined in: %s\n\n' "${NG_WATCH_FILE}"
  else
    ng_print_header "创建完整性基线"
    printf '扫描路径配置：%s\n\n' "${NG_WATCH_FILE}"
  fi

  : > "${baseline_file}"
  local total_files=0
  local skipped_paths=0
  
  while IFS= read -r watch_path; do
    [[ -n "${watch_path}" && "${watch_path}" != \#* ]] || continue
    if [[ -e "${watch_path}" ]]; then
      if [[ -r "${watch_path}" ]]; then
        local file_count
        file_count=$(find "${watch_path}" -type f 2>/dev/null | wc -l)
        find "${watch_path}" -type f -exec sha256sum {} \; >> "${baseline_file}" 2>/dev/null || true
        if [[ "${NG_LANG}" == "en" ]]; then
          printf '  ✓ %s (%d files)\n' "${watch_path}" "${file_count}"
        else
          printf '  ✓ %s（%d 个文件）\n' "${watch_path}" "${file_count}"
        fi
        total_files=$((total_files + file_count))
      else
        if [[ "${NG_LANG}" == "en" ]]; then
          printf '  ✗ %s (not readable)\n' "${watch_path}"
        else
          printf '  ✗ %s（不可读）\n' "${watch_path}"
        fi
        ((skipped_paths++)) || true
      fi
    else
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '  ✗ %s (not found)\n' "${watch_path}"
      else
        printf '  ✗ %s（不存在）\n' "${watch_path}"
      fi
      ((skipped_paths++)) || true
    fi
  done < "${NG_WATCH_FILE}"
  
  printf '\n'
  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Total files indexed: %d\n' "${total_files}"
    printf 'Baseline saved to: %s\n' "${baseline_file}"
    if [[ "${skipped_paths}" -gt 0 ]]; then
      printf 'Skipped paths: %d\n' "${skipped_paths}"
    fi
  else
    printf '已索引文件数：%d\n' "${total_files}"
    printf '基线保存至：%s\n' "${baseline_file}"
    if [[ "${skipped_paths}" -gt 0 ]]; then
      printf '跳过路径：%d\n' "${skipped_paths}"
    fi
  fi
}

ng_integrity_verify() {
  if [[ ! -f "${NG_INTEGRITY_DB}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No integrity baseline found. Create one first.\n'
    else
      printf '未找到完整性基线，请先生成。\n'
    fi
    return 1
  fi

  local changes=0

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Integrity Verification"
    printf 'Checking files against baseline...\n\n'
  else
    ng_print_header "完整性校验"
    printf '正在检查文件与基线的一致性...\n\n'
  fi

  while IFS= read -r line; do
    if echo "${line}" | grep -q "FAILED"; then
      printf '%s %s\n' "$(ng_color "${NG_C_ERR}" "✗")" "${line}"
      ((changes++)) || true
    elif echo "${line}" | grep -q "OK"; then
      printf '%s %s\n' "$(ng_color "${NG_C_OK}" "✓")" "${line}"
    else
      printf '%s\n' "${line}"
    fi
  done < <(cd / && sha256sum -c "${NG_INTEGRITY_DB}" 2>&1 || true)

  if [[ "${changes}" -gt 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\n⚠️  %d file(s) have changed since baseline.\n' "${changes}"
    else
      printf '\n⚠️  有 %d 个文件自基线以来发生了变化。\n' "${changes}"
    fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\n✓ All files match the baseline.\n'
    else
      printf '\n✓ 所有文件与基线一致。\n'
    fi
  fi
}

ng_security_report() {
  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🛡 ServerHarbor Security Report"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "Failed Login Sources"
    local auth_log=""
    [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
    [[ -f /var/log/secure ]] && auth_log="/var/log/secure"
    if [[ -n "${auth_log}" ]]; then
      ng_report_kv_styled "Auth Log" "${auth_log}"
      local login_output
      login_output="$(grep -Ei 'Failed password' "${auth_log}" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -nr | head -5)" || true
      if [[ -n "${login_output}" ]]; then
        echo "${login_output}" | while IFS= read -r line; do
          ng_report_line "  ${line}"
        done
      else
        ng_report_line "  No failed login entries found."
      fi
    else
      ng_report_line "  No auth log found."
    fi
    ng_report_section_start "Suspicious Web Requests"
    local access_log="/var/log/nginx/access.log"
    if [[ -f "${access_log}" ]]; then
      local web_output
      web_output="$(grep -Ei 'wp-admin|phpmyadmin|\.env|select.+from|union.+select' "${access_log}" 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -nr | head -5)" || true
      if [[ -n "${web_output}" ]]; then
        echo "${web_output}" | while IFS= read -r line; do
          ng_report_line "  ${line}"
        done
      else
        ng_report_line "  No suspicious requests found."
      fi
    else
      ng_report_line "  No nginx access log found."
    fi
    ng_report_section_start "Listening Ports"
    ss -lntp 2>/dev/null | sed -n '1,15p' | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done || true
    ng_report_section_start "Firewall"
    if command -v ufw >/dev/null 2>&1; then
      ng_report_kv_styled "Backend" "ufw"
      ufw status verbose 2>/dev/null | while IFS= read -r line; do
        ng_report_line "  ${line}"
      done || true
    elif command -v firewall-cmd >/dev/null 2>&1; then
      ng_report_kv_styled "Backend" "firewalld"
      firewall-cmd --list-all 2>/dev/null | while IFS= read -r line; do
        ng_report_line "  ${line}"
      done || true
    elif command -v iptables >/dev/null 2>&1; then
      ng_report_kv_styled "Backend" "iptables"
      iptables -L -n --line-numbers 2>/dev/null | sed -n '1,15p' | while IFS= read -r line; do
        ng_report_line "  ${line}"
      done || true
    else
      ng_report_line "  No firewall tool found."
    fi
    ng_report_footer
  else
    ng_report_header "🛡 ServerHarbor 安全巡检报告"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "失败登录来源"
    local auth_log=""
    [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
    [[ -f /var/log/secure ]] && auth_log="/var/log/secure"
    if [[ -n "${auth_log}" ]]; then
      ng_report_kv_styled "日志文件" "${auth_log}"
      local login_output
      login_output="$(grep -Ei 'Failed password' "${auth_log}" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -nr | head -5)" || true
      if [[ -n "${login_output}" ]]; then
        echo "${login_output}" | while IFS= read -r line; do
          ng_report_line "  ${line}"
        done
      else
        ng_report_line "  未发现失败登录记录。"
      fi
    else
      ng_report_line "  未找到认证日志文件。"
    fi
    ng_report_section_start "可疑 Web 请求"
    local access_log="/var/log/nginx/access.log"
    if [[ -f "${access_log}" ]]; then
      local web_output
      web_output="$(grep -Ei 'wp-admin|phpmyadmin|\.env|select.+from|union.+select' "${access_log}" 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -nr | head -5)" || true
      if [[ -n "${web_output}" ]]; then
        echo "${web_output}" | while IFS= read -r line; do
          ng_report_line "  ${line}"
        done
      else
        ng_report_line "  未发现可疑请求特征。"
      fi
    else
      ng_report_line "  未找到 nginx 访问日志。"
    fi
    ng_report_section_start "监听端口"
    ss -lntp 2>/dev/null | sed -n '1,15p' | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done || true
    ng_report_section_start "防火墙"
    if command -v ufw >/dev/null 2>&1; then
      ng_report_kv_styled "后端" "ufw"
      ufw status verbose 2>/dev/null | while IFS= read -r line; do
        ng_report_line "  ${line}"
      done || true
    elif command -v firewall-cmd >/dev/null 2>&1; then
      ng_report_kv_styled "后端" "firewalld"
      firewall-cmd --list-all 2>/dev/null | while IFS= read -r line; do
        ng_report_line "  ${line}"
      done || true
    elif command -v iptables >/dev/null 2>&1; then
      ng_report_kv_styled "后端" "iptables"
      iptables -L -n --line-numbers 2>/dev/null | sed -n '1,15p' | while IFS= read -r line; do
        ng_report_line "  ${line}"
      done || true
    else
      ng_report_line "  未找到防火墙工具。"
    fi
    ng_report_footer
  fi
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

    if [[ -f "${NG_WATCH_FILE}" ]]; then
      local line_num=1
      while IFS= read -r path; do
        [[ -n "${path}" && "${path}" != \#* ]] || continue
        printf '  [%d] %s\n' "${line_num}" "${path}"
        ((line_num++)) || true
      done < "${NG_WATCH_FILE}"
    else
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '  (No paths configured)\n'
      else
        printf '  （未配置路径）\n'
      fi
    fi

    printf '\n'
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '  [1] Add path\n'
      printf '  [2] Remove path\n'
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
        local new_path
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter path to monitor (file or directory): '
        else
          printf '输入要监控的路径（文件或目录）：'
        fi
        ng_read_line new_path || return 130

        if [[ -n "${new_path}" ]]; then
          if [[ -e "${new_path}" ]]; then
            # Create watch file if it doesn't exist
            if [[ ! -f "${NG_WATCH_FILE}" ]]; then
              printf '# One path per line for integrity scan\n' > "${NG_WATCH_FILE}"
            fi
            echo "${new_path}" >> "${NG_WATCH_FILE}"
            if [[ "${NG_LANG}" == "en" ]]; then
              printf 'Path added: %s\n' "${new_path}"
            else
              printf '路径已添加：%s\n' "${new_path}"
            fi
          else
            if [[ "${NG_LANG}" == "en" ]]; then
              printf 'Path does not exist: %s\n' "${new_path}"
            else
              printf '路径不存在：%s\n' "${new_path}"
            fi
          fi
        fi
        ;;
      2)
        if [[ ! -f "${NG_WATCH_FILE}" ]] || [[ -z "$(grep -Ev '^\s*#|^\s*$' "${NG_WATCH_FILE}" 2>/dev/null)" ]]; then
          if [[ "${NG_LANG}" == "en" ]]; then
            printf 'No paths to remove.\n'
          else
            printf '没有可删除的路径。\n'
          fi
        else
          if [[ "${NG_LANG}" == "en" ]]; then
            printf 'Enter line number to remove: '
          else
            printf '输入要删除的行号：'
          fi
          local line_num
          ng_read_line line_num || return 130
          if [[ "${line_num}" =~ ^[0-9]+$ ]]; then
            sed -i "${line_num}d" "${NG_WATCH_FILE}"
            if [[ "${NG_LANG}" == "en" ]]; then
              printf 'Path removed.\n'
            else
              printf '路径已删除。\n'
            fi
          fi
        fi
        ;;
      3)
        cat > "${NG_WATCH_FILE}" <<'EOF'
# One path per line for integrity scan
/etc
/var/www
/root
EOF
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
    ng_print_header "Security Score Calculation"
    printf 'Calculating security score...\n'
  else
    ng_print_header "安全评分计算"
    printf '正在计算安全评分...\n'
  fi
  
  if [[ "${EUID}" -eq 0 ]]; then
    score=$((score - 10))
    issues+=("Running as root (-10)")
  fi
  
  if ! grep -qE '^[^#]*PasswordAuthentication no' /etc/ssh/sshd_config 2>/dev/null; then
    score=$((score - 15))
    issues+=("SSH password authentication enabled (-15)")
  fi
  
  if grep -qE '^[^#]*PermitRootLogin yes' /etc/ssh/sshd_config 2>/dev/null; then
    score=$((score - 20))
    issues+=("Root login permitted (-20)")
  fi
  
  if ! command -v ufw >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1 && ! command -v iptables >/dev/null 2>&1; then
    score=$((score - 25))
    issues+=("No firewall detected (-25)")
  fi
  
  local auth_log=""
  [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
  [[ -f /var/log/secure ]] && auth_log="/var/log/secure"
  
  if [[ -n "${auth_log}" ]]; then
    local failed_count
    failed_count=$(grep -c "Failed password" "${auth_log}" 2>/dev/null || echo 0)
    if [[ "${failed_count}" -gt 100 ]]; then
      score=$((score - 10))
      issues+=("High number of failed login attempts: ${failed_count} (-10)")
    fi
  fi
  
  if [[ "${score}" -lt 0 ]]; then
    score=0
  fi
  
  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nSecurity Score: %d/100\n' "${score}"
    if [[ "${#issues[@]}" -gt 0 ]]; then
      printf '\nIssues found:\n'
      for issue in "${issues[@]}"; do
        printf '  • %s\n' "${issue}"
      done
    else
      printf 'No major security issues found.\n'
    fi
  else
    printf '\n安全评分: %d/100\n' "${score}"
    if [[ "${#issues[@]}" -gt 0 ]]; then
      printf '\n发现的问题:\n'
      for issue in "${issues[@]}"; do
        printf '  • %s\n' "${issue}"
      done
    else
      printf '未发现重大安全问题。\n'
    fi
  fi
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
