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

ng_list_nodes() {
  if ! command -v jq >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "jq is required for node management."
    else
      ng_log "ERROR" "节点管理需要 jq。"
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
    printf '%-20s %-20s %-10s %-6s %-10s\n' "NAME" "HOST" "USER" "PORT" "AUTH"
    printf '%s\n' '---------------------------------------------------------------------'
  else
    printf '%-20s %-20s %-10s %-6s %-10s\n' "名称" "主机" "用户" "端口" "认证"
    printf '%s\n' '---------------------------------------------------------------------'
  fi

  jq -r '.servers[] | "\(.name)\t\(.host)\t\(.ssh.user // "root")\t\(.ssh.port // 22)\t\(.ssh.auth // "key")"' "${NG_NODES_FILE}" 2>/dev/null | while IFS=$'\t' read -r name host user port auth; do
    printf '%-20s %-20s %-10s %-6s %-10s\n' "${name}" "${host}" "${user}" "${port}" "${auth}"
  done
}

ng_test_node_ssh() {
  local name="$1"
  local host="$2"
  local user="$3"
  local port="$4"
  local auth="$5"
  local key="$6"

  local -a ssh_opts=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -p "${port}")

  if [[ "${auth}" == "key" ]]; then
    ssh_opts+=(-i "${key}")
  fi

  local output
  output=$(ssh "${ssh_opts[@]}" "${user}@${host}" "echo 'SSH_OK'" 2>&1) && {
    printf '%s\n' "OK"
    return 0
  } || {
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
    printf '%-20s %-20s %-15s %s\n' "NODE" "HOST" "STATUS" "DETAIL"
    printf '%s\n' '----------------------------------------------------------------------'
  else
    printf '%-20s %-20s %-15s %s\n' "节点" "主机" "状态" "详情"
    printf '%s\n' '----------------------------------------------------------------------'
  fi

  local node_name node_host node_user node_port node_auth node_key
  while read -r node; do
    node_name=$(echo "${node}" | jq -r '.name')
    node_host=$(echo "${node}" | jq -r '.host')
    node_user=$(echo "${node}" | jq -r '.ssh.user // "root"')
    node_port=$(echo "${node}" | jq -r '.ssh.port // 22')
    node_auth=$(echo "${node}" | jq -r '.ssh.auth // "key"')
    node_key=$(echo "${node}" | jq -r '.ssh.key // "~/.ssh/id_ed25519"')

    local status detail
    status=$(ng_test_node_ssh "${node_name}" "${node_host}" "${node_user}" "${node_port}" "${node_auth}" "${node_key}") || true

    case "${status}" in
      OK)
        if [[ "${NG_LANG}" == "en" ]]; then detail="✓ Connected"; else detail="✓ 已连接"; fi
        status="OK"
        ;;
      CONN_REFUSED)
        if [[ "${NG_LANG}" == "en" ]]; then detail="SSH port closed"; else detail="SSH 端口关闭"; fi
        status="FAIL"
        ;;
      TIMEOUT)
        if [[ "${NG_LANG}" == "en" ]]; then detail="Connection timeout"; else detail="连接超时"; fi
        status="FAIL"
        ;;
      AUTH_FAILED)
        if [[ "${NG_LANG}" == "en" ]]; then detail="Authentication failed"; else detail="认证失败"; fi
        status="FAIL"
        ;;
      KEY_MISMATCH)
        if [[ "${NG_LANG}" == "en" ]]; then detail="Host key mismatch"; else detail="主机密钥不匹配"; fi
        status="FAIL"
        ;;
      KEY_NOT_FOUND)
        if [[ "${NG_LANG}" == "en" ]]; then detail="SSH key not found"; else detail="SSH 密钥未找到"; fi
        status="FAIL"
        ;;
      *)
        if [[ "${NG_LANG}" == "en" ]]; then detail="Unknown error"; else detail="未知错误"; fi
        status="FAIL"
        ;;
    esac

    printf '%-20s %-20s %-15s %s\n' "${node_name}" "${node_host}" "${status}" "${detail}"
  done < <(jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null)
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
    ng_print_header "Batch Command Execution"
    printf 'Command: %s\n\n' "${command}"
    printf '%-20s %-10s %s\n' "NODE" "STATUS" "OUTPUT"
    printf '%s\n' '---------------------------------------------------------------------'
  else
    ng_print_header "批量执行命令"
    printf '命令: %s\n\n' "${command}"
    printf '%-20s %-10s %s\n' "节点" "状态" "输出"
    printf '%s\n' '---------------------------------------------------------------------'
  fi

  {
    jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null | while read -r node; do
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
      output=$(ssh "${ssh_opts[@]}" "${user}@${host}" "${command}" 2>&1) && status="OK" || status="FAIL"
      printf '%-20s %-10s %s\n' "${name}" "${status}" "$(echo "${output}" | head -1)"
    done
  } | tee "${output_file}"

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nResults saved to: %s\n' "${output_file}"
  else
    printf '\n结果已保存至: %s\n' "${output_file}"
  fi
}

ng_sync_to_all_nodes() {
  local source_file="$1"
  local remote_path="$2"

  if [[ ! -f "${source_file}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "Source file not found: ${source_file}"
    else
      ng_log "ERROR" "源文件不存在: ${source_file}"
    fi
    return 1
  fi

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
    ng_print_header "Configuration Sync"
    printf 'Source: %s\n' "${source_file}"
    printf 'Target: %s\n\n' "${remote_path}"
    printf 'Syncing to all nodes...\n'
  else
    ng_print_header "配置文件同步"
    printf '源文件: %s\n' "${source_file}"
    printf '目标路径: %s\n\n' "${remote_path}"
    printf '正在同步到所有节点...\n'
  fi

  local success=0
  local failed=0

  while read -r node; do
    local name host user port auth key
    name=$(echo "${node}" | jq -r '.name')
    host=$(echo "${node}" | jq -r '.host')
    user=$(echo "${node}" | jq -r '.ssh.user // "root"')
    port=$(echo "${node}" | jq -r '.ssh.port // 22')
    auth=$(echo "${node}" | jq -r '.ssh.auth // "key"')
    key=$(echo "${node}" | jq -r '.ssh.key // "~/.ssh/id_ed25519"')

    local -a scp_opts=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -P "${port}")
    if [[ "${auth}" == "key" ]]; then
      scp_opts+=(-i "${key}")
    fi

    if scp "${scp_opts[@]}" "${source_file}" "${user}@${host}:${remote_path}" 2>/dev/null; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '  ✓ %s: synced\n' "${name}"
      else
        printf '  ✓ %s: 同步成功\n' "${name}"
      fi
      ((success++)) || true
    else
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '  ✗ %s: failed\n' "${name}"
      else
        printf '  ✗ %s: 失败\n' "${name}"
      fi
      ((failed++)) || true
    fi
  done < <(jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null)

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nSync completed: %d success, %d failed\n' "${success}" "${failed}"
  else
    printf '\n同步完成: %d 成功, %d 失败\n' "${success}" "${failed}"
  fi
}

ng_deploy_ssh_keys() {
  if ! ng_ensure_jq; then
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

  if [[ ! -f ~/.ssh/id_ed25519 ]] && [[ ! -f ~/.ssh/id_rsa ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No SSH key found. Generating new key...\n'
    else
      printf '未找到 SSH 密钥，正在生成...\n'
    fi
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q 2>/dev/null || ssh-keygen -t rsa -f ~/.ssh/id_rsa -N "" -q 2>/dev/null
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Deploying SSH keys to all nodes...\n\n'
  else
    printf '正在部署 SSH 密钥到所有节点...\n\n'
  fi

  local success=0
  local failed=0

  while read -r node; do
    local node_name node_host node_user node_port
    node_name=$(echo "${node}" | jq -r '.name')
    node_host=$(echo "${node}" | jq -r '.host')
    node_user=$(echo "${node}" | jq -r '.ssh.user // "root"')
    node_port=$(echo "${node}" | jq -r '.ssh.port // 22')

    printf '  %-20s ' "${node_name}"

    if ssh-copy-id -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "${node_port}" "${node_user}@${node_host}" 2>/dev/null; then
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '✓ Deployed\n'
      else
        printf '✓ 已部署\n'
      fi
      ((success++)) || true
    else
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '✗ Failed\n'
      else
        printf '✗ 失败\n'
      fi
      ((failed++)) || true
    fi
  done < <(jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null)

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nDeployment completed: %d success, %d failed\n' "${success}" "${failed}"
  else
    printf '\n部署完成: %d 成功, %d 失败\n' "${success}" "${failed}"
  fi
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
    ping_result="up"
    latency="$(echo "${ping_output}" | awk -F'time=' 'END {print $2}' | awk '{print $1}' || echo n/a)"
  else
    ping_result="down"
    latency="timeout"
  fi

  if nc -z -w "${NG_PROBE_TIMEOUT}" "${peer_host}" 22 2>/dev/null; then
    ssh_result="open"
  elif timeout "${NG_PROBE_TIMEOUT}" bash -c "cat < /dev/null > /dev/tcp/${peer_host}/22" >/dev/null 2>&1; then
    ssh_result="open"
  else
    ssh_result="closed"
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

  local count
  count=$(jq '.servers | length' "${NG_NODES_FILE}" 2>/dev/null || echo 0)

  if [[ "${count}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf 'No nodes configured.\n'
    else
      printf '未配置节点。\n'
    fi
    return 1
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nConfigured nodes:\n'
  else
    printf '\n已配置的节点：\n'
  fi

  local idx=1
  while IFS=$'\t' read -r name host user port; do
    printf '  [%d] %s (%s)\n' "${idx}" "${name}" "${host}"
    ((idx++)) || true
  done < <(jq -r '.servers[] | select(.enabled != false) | "\(.name)\t\(.host)\t\(.ssh.user // "root")\t\(.ssh.port // 22)"' "${NG_NODES_FILE}" 2>/dev/null)

  printf '  [a] %s\n' "$( [[ "${NG_LANG}" == "en" ]] && echo "All" || echo "全部" )"
  printf '\n'

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Select nodes (comma-separated, e.g. 1,3 or a): '
  else
    printf '选择节点（逗号分隔，如 1,3 或 a）：'
  fi

  local selection
  ng_read_line selection || return 130

  if [[ "${selection}" == "a" ]] || [[ "${selection}" == "A" ]] || [[ -z "${selection}" ]]; then
    printf '%s\n' "all"
    return 0
  fi

  printf '%s\n' "${selection}"
}

ng_generate_join_command() {
  local main_host
  main_host=$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Register New Node"
    printf 'On this server, run:\n\n'
    printf '%s\n' "$(ng_color "${NG_C_ACCENT}" "bash join.sh")"
    printf '\n'
    printf '%s\n' "$(ng_color "${NG_C_DIM}" "Or if installed:")"
    printf '%s\n' "$(ng_color "${NG_C_ACCENT}" "shr → [3] Node Management → [9] Register new node")"
    printf '\n'
    printf '%s\n' "$(ng_color "${NG_C_DIM}" "Requires SSH access from this server to the new server.")"
  else
    ng_print_header "注册新节点"
    printf '在本服务器上执行：\n\n'
    printf '%s\n' "$(ng_color "${NG_C_ACCENT}" "bash join.sh")"
    printf '\n'
    printf '%s\n' "$(ng_color "${NG_C_DIM}" "或安装版：")"
    printf '%s\n' "$(ng_color "${NG_C_ACCENT}" "shr → [3] 节点管理 → [9] 注册新节点")"
    printf '\n'
    printf '%s\n' "$(ng_color "${NG_C_DIM}" "需要从本服务器 SSH 到新服务器。")"
  fi
}

ng_node_menu() {
  local choice

  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛰 Node Management" "Multi-server management with SSH"
      ng_print_option "1" "📋" "List nodes" "Show all configured nodes"
      ng_print_option "2" "➕" "Add node" "Add a new server node"
      ng_print_option "3" "➖" "Remove node" "Remove a server node"
      ng_print_option "4" "🔍" "Test SSH" "Test SSH connectivity to selected nodes"
      ng_print_option "5" "📡" "Probe nodes" "Check ICMP, SSH, latency and local health"
      ng_print_option "6" "⚡" "Batch execute" "Run command on selected nodes"
      ng_print_option "7" "📁" "Sync config" "Sync config file to selected nodes"
      ng_print_option "8" "🔑" "Deploy SSH keys" "Deploy SSH keys to selected nodes"
      ng_print_option "9" "🔗" "Register new node" "Register a new server via SSH from this server"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛰 节点管理" "基于 SSH 的多服务器管理"
      ng_print_option "1" "📋" "列出节点" "显示所有已配置的节点"
      ng_print_option "2" "➕" "添加节点" "添加新的服务器节点"
      ng_print_option "3" "➖" "删除节点" "删除服务器节点"
      ng_print_option "4" "🔍" "测试 SSH" "测试选中节点的 SSH 连接"
      ng_print_option "5" "📡" "探测节点" "检查 ICMP、SSH、延迟和本机健康"
      ng_print_option "6" "⚡" "批量执行" "在选中节点上执行命令"
      ng_print_option "7" "📁" "配置同步" "将配置文件同步到选中节点"
      ng_print_option "8" "🔑" "部署 SSH 密钥" "部署 SSH 密钥到选中节点"
      ng_print_option "9" "🔗" "注册新节点" "从本服务器通过 SSH 注册新服务器"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_list_nodes ;;
      2)
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
            ;;
          *)
            auth="key"
            if [[ "${NG_LANG}" == "en" ]]; then
              printf 'Enter SSH key path (default: ~/.ssh/id_ed25519): '
            else
              printf '输入 SSH 密钥路径（默认: ~/.ssh/id_ed25519）：'
            fi
            ng_read_line key || return 130
            key="${key:-~/.ssh/id_ed25519}"
            ;;
        esac

        if [[ -n "${alias}" && -n "${host}" ]]; then
          ng_add_node "${alias}" "${host}" "${user}" "${port}" "${auth}" "${key}"
        fi
        ;;
      3)
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter node alias to remove: '
        else
          printf '输入要删除的节点别名：'
        fi
        local remove_alias
        ng_read_line remove_alias || return 130
        if [[ -n "${remove_alias}" ]]; then
          ng_remove_node "${remove_alias}"
        fi
        ;;
      4) ng_test_all_nodes ;;
      5) ng_probe_all_peers ;;
      6)
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter command to execute: '
        else
          printf '输入要执行的命令：'
        fi
        local cmd
        ng_read_line cmd || return 130
        if [[ -n "${cmd}" ]]; then
          ng_run_on_all_nodes "${cmd}"
        fi
        ;;
      7)
        local src_file remote_path
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter source file path: '
        else
          printf '输入源文件路径：'
        fi
        ng_read_line src_file || return 130

        if [[ -n "${src_file}" ]]; then
          local -a target_nodes=()
          local selection
          selection="$(ng_select_nodes)" || continue
          if [[ "${selection}" == "all" ]]; then
            if [[ "${NG_LANG}" == "en" ]]; then
              printf 'Enter remote target path: '
            else
              printf '输入远程目标路径：'
            fi
            ng_read_line remote_path || return 130
            if [[ -n "${remote_path}" ]]; then
              ng_sync_to_all_nodes "${src_file}" "${remote_path}"
            fi
          else
            while IFS=',' read -r num; do
              num=$(echo "${num}" | tr -d ' ')
              if [[ "${num}" =~ ^[0-9]+$ ]]; then
                target_nodes+=("${num}")
              fi
            done <<< "${selection}"

            for node_idx in "${target_nodes[@]}"; do
              local node_name node_host
              node_name=$(jq -r ".servers[$((node_idx-1))].name" "${NG_NODES_FILE}" 2>/dev/null)
              node_host=$(jq -r ".servers[$((node_idx-1))].host" "${NG_NODES_FILE}" 2>/dev/null)
              if [[ -z "${node_name}" || "${node_name}" == "null" ]]; then
                continue
              fi

              if [[ "${NG_LANG}" == "en" ]]; then
                printf '\nNode %s (%s):\n' "${node_name}" "${node_host}"
                printf '  Remote target path: '
              else
                printf '\n节点 %s (%s)：\n' "${node_name}" "${node_host}"
                printf '  远程目标路径：'
              fi
              ng_read_line remote_path || return 130
              remote_path="${remote_path:-/tmp/$(basename "${src_file}")}"

              local node_user node_port node_auth node_key
              node_user=$(jq -r ".servers[$((node_idx-1))].ssh.user // \"root\"" "${NG_NODES_FILE}" 2>/dev/null)
              node_port=$(jq -r ".servers[$((node_idx-1))].ssh.port // 22" "${NG_NODES_FILE}" 2>/dev/null)
              node_auth=$(jq -r ".servers[$((node_idx-1))].ssh.auth // \"key\"" "${NG_NODES_FILE}" 2>/dev/null)
              node_key=$(jq -r ".servers[$((node_idx-1))].ssh.key // \"~/.ssh/id_ed25519\"" "${NG_NODES_FILE}" 2>/dev/null)

              local -a scp_opts=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -P "${node_port}")
              if [[ "${node_auth}" == "key" ]]; then
                scp_opts+=(-i "${node_key}")
              fi

              if scp "${scp_opts[@]}" "${src_file}" "${node_user}@${node_host}:${remote_path}" 2>/dev/null; then
                printf '  ✓ %s\n' "$( [[ "${NG_LANG}" == "en" ]] && echo "Synced" || echo "同步成功" )"
              else
                printf '  ✗ %s\n' "$( [[ "${NG_LANG}" == "en" ]] && echo "Failed" || echo "失败" )"
              fi
            done
          fi
        fi
        ;;
      8) ng_deploy_ssh_keys ;;
      9) ng_generate_join_command ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || return 130
  done
}
