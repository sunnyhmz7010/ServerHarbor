#!/usr/bin/env bash

set -euo pipefail

ng_init_nodes() {
  if [[ ! -f "${NG_NODES_FILE}" ]]; then
    mkdir -p "$(dirname "${NG_NODES_FILE}")"
    cat > "${NG_NODES_FILE}" <<'EOF'
{
  "defaults": {
    "ssh": {
      "user": "root",
      "port": 22,
      "key": "~/.ssh/id_ed25519"
    }
  },
  "servers": []
}
EOF
  fi
}

ng_ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'jq not found. Installing...\n'
  else
    printf '未找到 jq，正在安装...\n'
  fi

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq jq
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y jq
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "Cannot install jq automatically. Please install it manually."
    else
      ng_log "ERROR" "无法自动安装 jq，请手动安装。"
    fi
    return 1
  fi
}

ng_add_node() {
  local name="$1"
  local host="$2"
  local user="${3:-root}"
  local port="${4:-22}"
  local auth="${5:-key}"
  local key="${6:-~/.ssh/id_ed25519}"
  local tags="${7:-}"

  if [[ -z "${name}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "Node name is required."
    else
      ng_log "ERROR" "节点名称不能为空。"
    fi
    return 1
  fi

  if [[ -z "${host}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "Host is required."
    else
      ng_log "ERROR" "主机地址不能为空。"
    fi
    return 1
  fi

  if ! [[ "${port}" =~ ^[0-9]+$ ]] || [[ "${port}" -lt 1 ]] || [[ "${port}" -gt 65535 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "Invalid port number: ${port} (must be 1-65535)"
    else
      ng_log "ERROR" "无效端口号: ${port}（必须为 1-65535）"
    fi
    return 1
  fi

  if [[ "${auth}" != "key" && "${auth}" != "password" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "Invalid auth method: ${auth} (must be 'key' or 'password')"
    else
      ng_log "ERROR" "无效认证方式: ${auth}（必须为 'key' 或 'password'）"
    fi
    return 1
  fi

  ng_init_nodes

  if ! ng_ensure_jq; then
    return 1
  fi

  if jq -e --arg n "${name}" '.servers[] | select(.name == $n)' "${NG_NODES_FILE}" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "Node '${name}' already exists. Use edit to modify."
    else
      ng_log "WARN" "节点 '${name}' 已存在，请使用编辑功能修改。"
    fi
    return 1
  fi

  local tmp_file="${NG_NODES_FILE}.tmp"
  jq --arg name "${name}" \
     --arg host "${host}" \
     --arg user "${user}" \
     --arg port "${port}" \
     --arg auth "${auth}" \
     --arg key "${key}" \
     --arg tags "${tags}" \
     '.servers += [{
       "name": $name,
       "host": $host,
       "ssh": {
         "user": $user,
         "port": ($port | tonumber),
         "auth": $auth,
         "key": $key
       },
       "tags": (if $tags != "" then ($tags | split(",") | map(gsub("^\\s+|\\s+$"; ""))) else [] end),
       "enabled": true
     }]' "${NG_NODES_FILE}" > "${tmp_file}" && mv -f "${tmp_file}" "${NG_NODES_FILE}"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_log "INFO" "Node added: ${name} (${host})"
  else
    ng_log "INFO" "节点已添加: ${name} (${host})"
  fi
}

ng_remove_node() {
  local name="$1"

  if ! command -v jq >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "jq is required for node management."
    else
      ng_log "ERROR" "节点管理需要 jq。"
    fi
    return 1
  fi

  if ! jq -e --arg n "${name}" '.servers[] | select(.name == $n)' "${NG_NODES_FILE}" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "Node '${name}' not found."
    else
      ng_log "WARN" "节点 '${name}' 不存在。"
    fi
    return 1
  fi

  local tmp_file="${NG_NODES_FILE}.tmp"
  jq --arg name "${name}" '.servers |= map(select(.name != $name))' "${NG_NODES_FILE}" > "${tmp_file}" && mv -f "${tmp_file}" "${NG_NODES_FILE}"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_log "INFO" "Node removed: ${name}"
  else
    ng_log "INFO" "节点已删除: ${name}"
  fi
}

ng_test_node_ssh() {
  local name="$1"
  local host="$2"
  local user="$3"
  local port="$4"
  local auth="$5"
  local key="$6"

  local output

  if [[ "${auth}" == "password" ]]; then
    if ! command -v sshpass >/dev/null 2>&1; then
      printf '%s\n' "AUTH_FAILED"
      return 1
    fi
    output=$(SSHPASS="${key}" sshpass -e ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "${port}" "${user}@${host}" "echo 'SSH_OK'" 2>&1) && {
      printf '%s\n' "OK"
      return 0
    }
  else
    output=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -p "${port}" -i "${key}" "${user}@${host}" "echo 'SSH_OK'" 2>&1) && {
      printf '%s\n' "OK"
      return 0
    }
  fi

  {
    if [[ "${output}" == *"connection refused"* ]]; then
      printf '%s\n' "CONN_REFUSED"
    elif [[ "${output}" == *"connection timed out"* ]] || [[ "${output}" == *"no route to host"* ]]; then
      printf '%s\n' "TIMEOUT"
    elif [[ "${output}" == *"permission denied"* ]]; then
      printf '%s\n' "AUTH_FAILED"
    elif [[ "${output}" == *"host key verification failed"* ]]; then
      printf '%s\n' "KEY_MISMATCH"
    elif [[ "${output}" == *"no such file"* ]] || [[ "${output}" == *"not found"* ]]; then
      printf '%s\n' "KEY_NOT_FOUND"
    else
      printf '%s\n' "UNKNOWN"
    fi
    return 1
  }
}

ng_test_all_nodes() {
  if ! ng_ensure_jq; then
    return 1
  fi

  local count
  count=$(jq '.servers | length' "${NG_NODES_FILE}" 2>/dev/null || echo 0)

  if [[ "${count}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No nodes to test.\n'
    else
      printf '没有可测试的节点。\n'
    fi
    return 0
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🔍 SSH Connectivity Test"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "Test Results"
  else
    ng_report_header "🔍 SSH 连接测试"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "测试结果"
  fi

  local total=0 passed=0 failed=0

  while read -r node; do
    local node_name node_host node_user node_port node_auth node_key
    node_name=$(echo "${node}" | jq -r '.name')
    node_host=$(echo "${node}" | jq -r '.host')
    node_user=$(echo "${node}" | jq -r '.ssh.user // "root"')
    node_port=$(echo "${node}" | jq -r '.ssh.port // 22')
    node_auth=$(echo "${node}" | jq -r '.ssh.auth // "key"')
    node_key=$(echo "${node}" | jq -r '.ssh.key // "~/.ssh/id_ed25519"')

    local status detail
    status=$(ng_test_node_ssh "${node_name}" "${node_host}" "${node_user}" "${node_port}" "${node_auth}" "${node_key}") || true

    case "${status}" in
      OK) if [[ "${NG_LANG}" == "en" ]]; then detail="✓ Connected"; else detail="✓ 已连接"; fi; ((passed++)) || true ;;
      CONN_REFUSED) if [[ "${NG_LANG}" == "en" ]]; then detail="SSH port closed"; else detail="SSH 端口关闭"; fi; ((failed++)) || true ;;
      TIMEOUT) if [[ "${NG_LANG}" == "en" ]]; then detail="Connection timeout"; else detail="连接超时"; fi; ((failed++)) || true ;;
      AUTH_FAILED) if [[ "${NG_LANG}" == "en" ]]; then detail="Authentication failed"; else detail="认证失败"; fi; ((failed++)) || true ;;
      KEY_MISMATCH) if [[ "${NG_LANG}" == "en" ]]; then detail="Host key mismatch"; else detail="主机密钥不匹配"; fi; ((failed++)) || true ;;
      KEY_NOT_FOUND) if [[ "${NG_LANG}" == "en" ]]; then detail="SSH key not found"; else detail="SSH 密钥未找到"; fi; ((failed++)) || true ;;
      *) if [[ "${NG_LANG}" == "en" ]]; then detail="Unknown error"; else detail="未知错误"; fi; ((failed++)) || true ;;
    esac
    ((total++)) || true

    printf '%s   %-20s %-20s %-15s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${node_name}" "${node_host}" "${status}" "${detail}"
  done < <(jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null)

  ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Tested:" || echo "测试:")" "${total}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Passed:" || echo "通过:")" "${passed}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Failed:" || echo "失败:")" "${failed}"
  if [[ "${failed}" -gt 0 ]]; then
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_WARN}" "⚠️  $( [[ "${NG_LANG}" == "en" ]] && echo "Some connections failed" || echo "部分连接失败" )")"
  else
    ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_OK}" "✅ $( [[ "${NG_LANG}" == "en" ]] && echo "All passed" || echo "全部通过" )")"
  fi
  ng_report_footer
}

ng_run_on_all_nodes() {
  local command="$1"
  local output_file="${NG_STATE_DIR}/${NG_HOSTNAME}-batch-exec.state"

  if ! command -v jq >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "jq is required."
    else
      ng_log "ERROR" "需要 jq。"
    fi
    return 1
  fi

  local count
  count=$(jq '.servers | length' "${NG_NODES_FILE}" 2>/dev/null || echo 0)

  if [[ "${count}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No nodes configured.\n'
    else
      printf '未配置节点。\n'
    fi
    return 0
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "⚡ Batch Execute"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_meta "Command" "${command}"
    ng_report_section_start "Results"
  else
    ng_report_header "⚡ 批量执行"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_meta "命令" "${command}"
    ng_report_section_start "执行结果"
  fi

  local total=0 passed=0 failed=0

  local -a lines=()
  while read -r node; do
    local name host user port auth key
    name=$(echo "${node}" | jq -r '.name')
    host=$(echo "${node}" | jq -r '.host')
    user=$(echo "${node}" | jq -r '.ssh.user // "root"')
    port=$(echo "${node}" | jq -r '.ssh.port // 22')
    auth=$(echo "${node}" | jq -r '.ssh.auth // "key"')
    key=$(echo "${node}" | jq -r '.ssh.key // "~/.ssh/id_ed25519"')

    local -a ssh_opts=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p "${port}")
    if [[ "${auth}" == "key" ]]; then
      ssh_opts+=(-i "${key}")
    fi

    local output status
    if [[ "${auth}" == "password" ]] && command -v sshpass >/dev/null 2>&1; then
      output=$(SSHPASS="${key}" sshpass -e ssh "${ssh_opts[@]}" "${user}@${host}" "${command}" 2>&1) && status="OK" || status="FAIL"
    else
      output=$(ssh "${ssh_opts[@]}" "${user}@${host}" "${command}" 2>&1) && status="OK" || status="FAIL"
    fi
    local first_line
    first_line=$(echo "${output}" | head -1)
    local line
    line=$(printf '%s   %-20s %-10s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${name}" "${status}" "${first_line}")
    printf '%s' "${line}"
    lines+=("${line}")

    if [[ "${status}" == "OK" ]]; then ((passed++)) || true; else ((failed++)) || true; fi
    ((total++)) || true
  done < <(jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null)

  printf '%s\n' "${lines[@]}" > "${output_file}"

  ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Total:" || echo "总计:")" "${total}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Passed:" || echo "通过:")" "${passed}"
  ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Failed:" || echo "失败:")" "${failed}"
  ng_report_footer
}

ng_collect_local_probe() {
  local state_file="${NG_STATE_DIR}/${NG_HOSTNAME}-local.state"
  local tmp_file="${state_file}.tmp"

  {
    printf 'timestamp=%s\n' "$(date '+%s')"
    printf 'host=%s\n' "${NG_HOSTNAME}"
    printf 'uptime=%s\n' "$(uptime -p 2>/dev/null || uptime)"
    printf 'load=%s\n' "$(ng_system_load)"
    printf 'disk_root=%s\n' "$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' || echo unknown)"
    printf 'mem_used=%s\n' "$(free -m 2>/dev/null | awk '/Mem:/ {printf "%s/%sMB", $3, $2}' || echo unknown)"
    printf 'ssh=%s\n' "$(ng_service_state sshd)"
  } > "${tmp_file}"

  if mv -f "${tmp_file}" "${state_file}" 2>/dev/null; then
    printf '%s\n' "${state_file}"
  else
    rm -f "${tmp_file}" 2>/dev/null
    ng_log "ERROR" "$( [[ "${NG_LANG}" == "en" ]] && echo "Failed to write state file" || echo "写入状态文件失败" )"
    return 1
  fi
}

ng_probe_single_peer() {
  local peer_host="$1"
  local peer_alias="$2"
  local ping_result ssh_result latency
  local ping_output

  ping_output="$(ping -c 1 -W "${NG_PROBE_TIMEOUT}" "${peer_host}" 2>/dev/null)" || true

  if [[ -n "${ping_output}" ]] && [[ "${ping_output}" == *"bytes from"* ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then ping_result="up"; else ping_result="通"; fi
    latency="$(echo "${ping_output}" | awk -F'time=' 'END {print $2}' | awk '{print $1}' || echo n/a)"
  else
    if [[ "${NG_LANG}" == "en" ]]; then ping_result="down"; else ping_result="断"; fi
    latency="-"
  fi

  if nc -z -w "${NG_PROBE_TIMEOUT}" "${peer_host}" 22 2>/dev/null; then
    if [[ "${NG_LANG}" == "en" ]]; then ssh_result="open"; else ssh_result="开"; fi
  elif timeout "${NG_PROBE_TIMEOUT}" bash -c "cat < /dev/null > /dev/tcp/${peer_host}/22" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then ssh_result="open"; else ssh_result="开"; fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then ssh_result="closed"; else ssh_result="关"; fi
  fi

  printf '%-16s %-24s %-8s %-10s %s\n' "${peer_alias}" "${peer_host}" "${ping_result}" "${ssh_result}" "${latency}"
}

ng_probe_all_peers() {
  local output_file="${NG_STATE_DIR}/${NG_HOSTNAME}-peers.state"

  {
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'Peer Alias       Peer Host                ICMP     SSH Port   Latency\n'
      printf '%s\n' '---------------------------------------------------------------------'
    else
      printf '节点别名           主机地址                 ICMP     SSH端口    延迟\n'
      printf '%s\n' '---------------------------------------------------------------------'
    fi

    if [[ -f "${NG_NODES_FILE}" ]] && command -v jq >/dev/null 2>&1; then
      jq -r '.servers[] | select(.enabled != false) | "\(.name),\(.host)"' "${NG_NODES_FILE}" 2>/dev/null | while IFS=',' read -r peer_alias peer_host; do
        [[ -n "${peer_alias}" && -n "${peer_host}" ]] || continue
        ng_probe_single_peer "${peer_host}" "${peer_alias}"
      done
    fi
  } | tee "${output_file}"

  local state_file
  state_file="$(ng_collect_local_probe)"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "🛰 ServerHarbor Probe Report"
    ng_report_meta "Generated At" "$(ng_timestamp)"
    ng_report_meta "Host" "${NG_HOSTNAME}"
    ng_report_section_start "Peer Matrix"
    while IFS= read -r line; do
      ng_report_line "  ${line}"
    done < "${output_file}"
    ng_report_section_start "Local Snapshot"
    while IFS= read -r line; do
      ng_report_line "  ${line}"
    done < "${state_file}"
    ng_report_footer
  else
    ng_report_header "🛰 ServerHarbor 节点探测报告"
    ng_report_meta "生成时间" "$(ng_timestamp)"
    ng_report_meta "主机" "${NG_HOSTNAME}"
    ng_report_section_start "节点矩阵"
    while IFS= read -r line; do
      ng_report_line "  ${line}"
    done < "${output_file}"
    ng_report_section_start "本机快照"
    while IFS= read -r line; do
      ng_report_line "  ${line}"
    done < "${state_file}"
    ng_report_footer
  fi
}

ng_select_nodes() {
  if ! ng_ensure_jq; then
    return 1
  fi

  if [[ ! -f "${NG_NODES_FILE}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No nodes file found.\n' >&2
    else
      printf '未找到节点配置文件。\n' >&2
    fi
    return 1
  fi

  local count
  count=$(jq '.servers | length' "${NG_NODES_FILE}" 2>/dev/null || echo "0")
  count=$(echo "${count}" | tr -d '[:space:]')
  : "${count:=0}"

  if [[ "${count}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No nodes configured.\n' >&2
    else
      printf '未配置节点。\n' >&2
    fi
    return 1
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nConfigured nodes:\n' >&2
  else
    printf '\n已配置的节点：\n' >&2
  fi

  local idx=1
  while IFS=$'\t' read -r name host; do
    printf '  [%d] %s (%s)\n' "${idx}" "${name}" "${host}" >&2
    ((idx++)) || true
  done < <(jq -r '.servers[] | select(.enabled != false) | "\(.name)\t\(.host)"' "${NG_NODES_FILE}" 2>/dev/null)

  printf '  [a] %s\n' "$( [[ "${NG_LANG}" == "en" ]] && echo "All" || echo "全部" )" >&2
  printf '\n' >&2

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Select nodes (comma-separated, e.g. 1,3 or a): ' >&2
  else
    printf '选择节点（逗号分隔，如 1,3 或 a）：' >&2
  fi

  local selection
  read -r selection < /dev/tty

  if [[ "${selection}" == "a" ]] || [[ "${selection}" == "A" ]] || [[ -z "${selection}" ]]; then
    printf '%s\n' "all"
    return 0
  fi

  local -a selected_names=()
  while IFS=',' read -r num; do
    num=$(echo "${num}" | tr -d ' ')
    if [[ "${num}" =~ ^[0-9]+$ ]] && [[ "${num}" -ge 1 ]] && [[ "${num}" -le "${idx}" ]]; then
      local sel_name
      sel_name=$(jq -r "[.servers[] | select(.enabled != false)][${num} - 1].name" "${NG_NODES_FILE}" 2>/dev/null)
      if [[ -n "${sel_name}" && "${sel_name}" != "null" ]]; then
        selected_names+=("${sel_name}")
      fi
    fi
  done <<< "${selection}"

  if [[ "${#selected_names[@]}" -eq 0 ]]; then
    printf '%s\n' "all"
  else
    printf '%s\n' "${selected_names[*]}"
  fi
}

ng_node_manage() {
  local choice

  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "📋 Node List" "Manage node configurations"
    else
      ng_print_title_box "📋 节点列表" "管理节点配置"
    fi

    printf '\n'
    local -a node_names=()
    local -a node_hosts=()
    local idx=1

    if command -v jq >/dev/null 2>&1 && [[ -f "${NG_NODES_FILE}" ]]; then
      while IFS=$'\t' read -r name host; do
        printf '  [%d] %-20s %s\n' "${idx}" "${name}" "${host}"
        node_names+=("${name}")
        node_hosts+=("${host}")
        ((idx++)) || true
      done < <(jq -r '.servers[] | select(.enabled != false) | "\(.name)\t\(.host)"' "${NG_NODES_FILE}" 2>/dev/null)
    fi

    if [[ "${idx}" -eq 1 ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '  (No nodes configured)\n'
      else
        printf '  （未配置节点）\n'
      fi
    fi

    printf '\n'
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '  [a] Add node\n'
      if [[ "${idx}" -gt 1 ]]; then
        printf '  [1-%d] Remove node by number\n' "$((idx-1))"
      fi
      printf '  [0] Back\n'
    else
      printf '  [a] 添加节点\n'
      if [[ "${idx}" -gt 1 ]]; then
        printf '  [1-%d] 输入序号删除节点\n' "$((idx-1))"
      fi
      printf '  [0] 返回\n'
    fi

    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      0) return 0 ;;

      a|A)
        local alias host user port auth key
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter node alias (e.g., hk-01): '
        else
          printf '输入节点别名（如 hk-01）：'
        fi
        ng_read_line alias || return 130

        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter host (IP or hostname): '
        else
          printf '输入主机（IP 或主机名）：'
        fi
        ng_read_line host || return 130

        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter SSH user (default: root): '
        else
          printf '输入 SSH 用户（默认: root）：'
        fi
        ng_read_line user || return 130
        user="${user:-root}"

        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter SSH port (default: 22): '
        else
          printf '输入 SSH 端口（默认: 22）：'
        fi
        ng_read_line port || return 130
        port="${port:-22}"

        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Authentication method:\n'
          printf '  [1] SSH key (default)\n'
          printf '  [2] Password\n'
        else
          printf '认证方式：\n'
          printf '  [1] SSH 密钥（默认）\n'
          printf '  [2] 密码\n'
        fi
        local auth_choice
        ng_read_line auth_choice || return 130

        case "${auth_choice}" in
          2)
            auth="password"
            if [[ "${NG_LANG}" == "en" ]]; then
              printf 'Enter password: '
            else
              printf '输入密码：'
            fi
            IFS= read -rs key < /dev/tty
            printf '\n'

            if ! command -v sshpass >/dev/null 2>&1; then
              if [[ "${EUID}" -eq 0 ]]; then
                if [[ "${NG_LANG}" == "en" ]]; then
                  printf 'Installing sshpass...\n'
                else
                  printf '正在安装 sshpass...\n'
                fi
                if command -v apt-get >/dev/null 2>&1; then apt-get install -y -qq sshpass 2>/dev/null || true
                elif command -v yum >/dev/null 2>&1; then yum install -y sshpass 2>/dev/null || true
                elif command -v dnf >/dev/null 2>&1; then dnf install -y sshpass 2>/dev/null || true
                fi
              fi
            fi
            ;;
          *)
            auth="key"
            local -a available_keys=()
            for kf in ~/.ssh/id_ed25519 ~/.ssh/id_rsa ~/.ssh/id_ecdsa ~/.ssh/id_dsa; do
              [[ -f "${kf}" ]] && available_keys+=("${kf}")
            done

            if [[ "${#available_keys[@]}" -eq 0 ]]; then
              if [[ "${NG_LANG}" == "en" ]]; then
                printf 'No SSH keys found. Generate one first (ssh-keygen).\n'
              else
                printf '~/.ssh/ 中未找到密钥，请先生成（ssh-keygen）。\n'
              fi
              continue
            fi

            if [[ "${#available_keys[@]}" -eq 1 ]]; then
              key="${available_keys[0]}"
              if [[ "${NG_LANG}" == "en" ]]; then
                printf 'Using SSH key: %s\n' "${key}"
              else
                printf '使用 SSH 密钥：%s\n' "${key}"
              fi
            else
              if [[ "${NG_LANG}" == "en" ]]; then
                printf 'Available SSH keys:\n'
              else
                printf '可用 SSH 密钥：\n'
              fi
              local ki=1
              for kf in "${available_keys[@]}"; do
                printf '  [%d] %s\n' "${ki}" "${kf}"
                ((ki++)) || true
              done
              if [[ "${NG_LANG}" == "en" ]]; then
                printf 'Select key (default 1): '
              else
                printf '选择密钥（默认 1）：'
              fi
              local key_choice
              ng_read_line key_choice || return 130
              key_choice="${key_choice:-1}"
              if [[ "${key_choice}" =~ ^[0-9]+$ ]] && [[ "${key_choice}" -ge 1 ]] && [[ "${key_choice}" -le "${#available_keys[@]}" ]]; then
                key="${available_keys[$((key_choice-1))]}"
              else
                key="${available_keys[0]}"
              fi
            fi
            ;;
        esac

        if [[ -n "${alias}" && -n "${host}" ]]; then
          if [[ "${NG_LANG}" == "en" ]]; then
            printf '\nTesting SSH %s@%s:%s ...\n' "${user}" "${host}" "${port}"
          else
            printf '\n正在测试 SSH 连接 %s@%s:%s ...\n' "${user}" "${host}" "${port}"
          fi

          local -a test_opts=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "${port}")
          local ssh_ok=0

          if [[ "${auth}" == "password" ]] && command -v sshpass >/dev/null 2>&1; then
            if SSHPASS="${key}" sshpass -e ssh "${test_opts[@]}" "${user}@${host}" "echo OK" >/dev/null 2>&1; then
              ssh_ok=1
            fi
          elif [[ "${auth}" == "key" ]]; then
            test_opts+=(-i "${key}")
            if ssh "${test_opts[@]}" "${user}@${host}" "echo OK" >/dev/null 2>&1; then
              ssh_ok=1
            fi
          fi

          if [[ "${ssh_ok}" -eq 1 ]]; then
            if [[ "${NG_LANG}" == "en" ]]; then
              printf '✓ SSH connected.\n'
            else
              printf '✓ SSH 连接成功。\n'
            fi
            ng_add_node "${alias}" "${host}" "${user}" "${port}" "${auth}" "${key}"
          else
            if [[ "${NG_LANG}" == "en" ]]; then
              printf '✗ SSH failed. Node not added.\n'
            else
              printf '✗ SSH 连接失败，节点未添加。\n'
            fi
          fi
        fi
        ng_press_enter || return 130
        ;;

      *)
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -lt "${idx}" ]]; then
          local remove_name="${node_names[$((choice-1))]}"
          if [[ "${NG_LANG}" == "en" ]]; then
            printf 'Remove node "%s"? [y/N]: ' "${remove_name}"
          else
            printf '删除节点 "%s"？[y/N]：' "${remove_name}"
          fi
          local confirm
          ng_read_line confirm || return 130
          if [[ "${confirm}" =~ ^[Yy] ]]; then
            ng_remove_node "${remove_name}"
          fi
        else
          ng_t invalid_option
        fi
        ng_press_enter || return 130
        ;;
    esac
  done
}

ng_node_menu() {
  local choice

  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛰 Node Management" "Multi-server management with SSH"
      ng_print_option "1" "📋" "Node list" "List / add / remove nodes"
      ng_print_option "2" "🔍" "Test SSH" "Test SSH connectivity to selected nodes"
      ng_print_option "3" "📡" "Probe nodes" "Check ICMP, SSH, latency and local health"
      ng_print_option "4" "⚡" "Batch execute" "Run command on selected nodes"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛰 节点管理" "基于 SSH 的多服务器管理"
      ng_print_option "1" "📋" "节点列表" "列出 / 添加 / 删除节点"
      ng_print_option "2" "🔍" "测试 SSH" "测试选中节点的 SSH 连接"
      ng_print_option "3" "📡" "探测节点" "检查 ICMP、SSH、延迟和本机健康"
      ng_print_option "4" "⚡" "批量执行" "在选中节点上执行命令"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_node_manage ;;

      2)
        local selection
        selection="$(ng_select_nodes)" || continue
        if [[ "${selection}" == "all" ]]; then
          ng_test_all_nodes
        else
          if [[ "${NG_LANG}" == "en" ]]; then
            ng_report_header "🔍 SSH Connectivity Test"
            ng_report_meta "Generated At" "$(ng_timestamp)"
            ng_report_meta "Host" "${NG_HOSTNAME}"
            ng_report_section_start "Test Results"
          else
            ng_report_header "🔍 SSH 连接测试"
            ng_report_meta "生成时间" "$(ng_timestamp)"
            ng_report_meta "主机" "${NG_HOSTNAME}"
            ng_report_section_start "测试结果"
          fi

          local total=0 passed=0 failed=0

          for node_name in ${selection}; do
            local node_host node_user node_port node_auth node_key
            node_host=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .host' "${NG_NODES_FILE}" 2>/dev/null)
            node_user=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.user // "root"' "${NG_NODES_FILE}" 2>/dev/null)
            node_port=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.port // 22' "${NG_NODES_FILE}" 2>/dev/null)
            node_auth=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.auth // "key"' "${NG_NODES_FILE}" 2>/dev/null)
            node_key=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.key // "~/.ssh/id_ed25519"' "${NG_NODES_FILE}" 2>/dev/null)
            if [[ -z "${node_host}" || "${node_host}" == "null" ]]; then continue; fi

            local status detail
            status=$(ng_test_node_ssh "${node_name}" "${node_host}" "${node_user}" "${node_port}" "${node_auth}" "${node_key}") || true

            case "${status}" in
              OK) if [[ "${NG_LANG}" == "en" ]]; then detail="✓ Connected"; else detail="✓ 已连接"; fi; ((passed++)) || true ;;
              CONN_REFUSED) if [[ "${NG_LANG}" == "en" ]]; then detail="SSH port closed"; else detail="SSH 端口关闭"; fi; ((failed++)) || true ;;
              TIMEOUT) if [[ "${NG_LANG}" == "en" ]]; then detail="Connection timeout"; else detail="连接超时"; fi; ((failed++)) || true ;;
              AUTH_FAILED) if [[ "${NG_LANG}" == "en" ]]; then detail="Authentication failed"; else detail="认证失败"; fi; ((failed++)) || true ;;
              KEY_MISMATCH) if [[ "${NG_LANG}" == "en" ]]; then detail="Host key mismatch"; else detail="主机密钥不匹配"; fi; ((failed++)) || true ;;
              KEY_NOT_FOUND) if [[ "${NG_LANG}" == "en" ]]; then detail="SSH key not found"; else detail="SSH 密钥未找到"; fi; ((failed++)) || true ;;
              *) if [[ "${NG_LANG}" == "en" ]]; then detail="Unknown error"; else detail="未知错误"; fi; ((failed++)) || true ;;
            esac
            ((total++)) || true

            printf '%s   %-20s %-20s %-15s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${node_name}" "${node_host}" "${status}" "${detail}"
          done

          ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
          ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Tested:" || echo "测试:")" "${total}"
          ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Passed:" || echo "通过:")" "${passed}"
          ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Failed:" || echo "失败:")" "${failed}"
          if [[ "${failed}" -gt 0 ]]; then
            ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_WARN}" "⚠️  $( [[ "${NG_LANG}" == "en" ]] && echo "Some connections failed" || echo "部分连接失败" )")"
          else
            ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Status:" || echo "状态:")" "$(ng_color "${NG_C_OK}" "✅ $( [[ "${NG_LANG}" == "en" ]] && echo "All passed" || echo "全部通过" )")"
          fi
          ng_report_footer
        fi
        ;;
      3)
        local selection
        selection="$(ng_select_nodes)" || continue
        if [[ "${selection}" == "all" ]]; then
          ng_probe_all_peers
        else
          if [[ "${NG_LANG}" == "en" ]]; then
            ng_report_header "🛰 ServerHarbor Probe Report"
            ng_report_meta "Generated At" "$(ng_timestamp)"
            ng_report_meta "Host" "${NG_HOSTNAME}"
            ng_report_section_start "Peer Matrix"
          else
            ng_report_header "🛰 ServerHarbor 节点探测报告"
            ng_report_meta "生成时间" "$(ng_timestamp)"
            ng_report_meta "主机" "${NG_HOSTNAME}"
            ng_report_section_start "节点矩阵"
          fi

          for node_name in ${selection}; do
            local node_host
            node_host=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .host' "${NG_NODES_FILE}" 2>/dev/null)
            if [[ -z "${node_host}" || "${node_host}" == "null" ]]; then continue; fi

            local ping_output ping_result ssh_result latency
            ping_output="$(ping -c 1 -W "${NG_PROBE_TIMEOUT}" "${node_host}" 2>/dev/null)" || true
            if [[ -n "${ping_output}" ]] && [[ "${ping_output}" == *"bytes from"* ]]; then
              ping_result="up"
              latency="$(echo "${ping_output}" | awk -F'time=' 'END {print $2}' | awk '{print $1}' || echo n/a)"
            else
              ping_result="down"
              latency="timeout"
            fi

            if nc -z -w "${NG_PROBE_TIMEOUT}" "${node_host}" 22 2>/dev/null; then
              ssh_result="open"
            elif timeout "${NG_PROBE_TIMEOUT}" bash -c "cat < /dev/null > /dev/tcp/${node_host}/22" >/dev/null 2>&1; then
              ssh_result="open"
            else
              ssh_result="closed"
            fi

            printf '%s   %-16s %-24s %-8s %-10s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${node_name}" "${node_host}" "${ping_result}" "${ssh_result}" "${latency}"
          done

          local state_file
          state_file="$(ng_collect_local_probe)"

          ng_report_section_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Local Snapshot" || echo "本机快照" )"
          while IFS= read -r line; do
            printf '%s   %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${line}"
          done < "${state_file}"
          ng_report_footer
        fi
        ;;
      4)
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter command to execute: '
        else
          printf '输入要执行的命令：'
        fi
        local cmd
        ng_read_line cmd || return 130
        if [[ -n "${cmd}" ]]; then
          local selection
          selection="$(ng_select_nodes)" || continue
          if [[ "${selection}" == "all" ]]; then
            ng_run_on_all_nodes "${cmd}"
          else
            if [[ "${NG_LANG}" == "en" ]]; then
              ng_report_header "⚡ Batch Execute"
              ng_report_meta "Generated At" "$(ng_timestamp)"
              ng_report_meta "Host" "${NG_HOSTNAME}"
              ng_report_meta "Command" "${cmd}"
              ng_report_section_start "Results"
            else
              ng_report_header "⚡ 批量执行"
              ng_report_meta "生成时间" "$(ng_timestamp)"
              ng_report_meta "主机" "${NG_HOSTNAME}"
              ng_report_meta "命令" "${cmd}"
              ng_report_section_start "执行结果"
            fi

            local total=0 passed=0 failed=0

            for node_name in ${selection}; do
              local node_host node_user node_port node_auth node_key
              node_host=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .host' "${NG_NODES_FILE}" 2>/dev/null)
              node_user=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.user // "root"' "${NG_NODES_FILE}" 2>/dev/null)
              node_port=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.port // 22' "${NG_NODES_FILE}" 2>/dev/null)
              node_auth=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.auth // "key"' "${NG_NODES_FILE}" 2>/dev/null)
              node_key=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.key // "~/.ssh/id_ed25519"' "${NG_NODES_FILE}" 2>/dev/null)
              if [[ -z "${node_host}" || "${node_host}" == "null" ]]; then continue; fi

              local -a ssh_opts=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p "${node_port}")
              if [[ "${node_auth}" == "key" ]]; then ssh_opts+=(-i "${node_key}"); fi

              local output status
              if [[ "${node_auth}" == "password" ]] && command -v sshpass >/dev/null 2>&1; then
                output=$(SSHPASS="${node_key}" sshpass -e ssh "${ssh_opts[@]}" "${node_user}@${node_host}" "${cmd}" 2>&1) && status="OK" || status="FAIL"
              else
                output=$(ssh "${ssh_opts[@]}" "${node_user}@${node_host}" "${cmd}" 2>&1) && status="OK" || status="FAIL"
              fi
              local first_line
              first_line=$(echo "${output}" | head -1)
              printf '%s   %-20s %-10s %s\n' "$(ng_color "${NG_C_PANEL}" "║")" "${node_name}" "${status}" "${first_line}"

              if [[ "${status}" == "OK" ]]; then ((passed++)) || true; else ((failed++)) || true; fi
              ((total++)) || true
            done

            ng_report_summary_start "$( [[ "${NG_LANG}" == "en" ]] && echo "Summary" || echo "摘要" )"
            ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Total:" || echo "总计:")" "${total}"
            ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Passed:" || echo "通过:")" "${passed}"
            ng_report_summary_kv "$([[ "${NG_LANG}" == "en" ]] && echo "Failed:" || echo "失败:")" "${failed}"
            ng_report_footer
          fi
        fi
        ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || return 130
  done
}
