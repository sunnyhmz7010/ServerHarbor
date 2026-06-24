#!/usr/bin/env bash

set -euo pipefail

# Node configuration file path
NG_NODES_FILE="${NG_DATA_ROOT}/config/servers.json"

# Initialize nodes file if it doesn't exist
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

# Read nodes from JSON file
ng_read_nodes() {
  ng_init_nodes
  if command -v jq >/dev/null 2>&1; then
    jq -r '.servers[] | select(.enabled != false) | "\(.name),\(.host),\(.ssh.user // .defaults.ssh.user // "root"),\(.ssh.port // .defaults.ssh.port // 22),\(.ssh.auth // "key"),\(.ssh.key // .defaults.ssh.key // "~/.ssh/id_ed25519")"' "${NG_NODES_FILE}" 2>/dev/null || true
  else
    # Fallback: simple parsing
    grep -o '"name": *"[^"]*"' "${NG_NODES_FILE}" 2>/dev/null | cut -d'"' -f4 || true
  fi
}

# Get node count
ng_node_count() {
  if command -v jq >/dev/null 2>&1; then
    jq '[.servers[] | select(.enabled != false)] | length' "${NG_NODES_FILE}" 2>/dev/null || echo 0
  else
    ng_read_nodes | wc -l | tr -d ' '
  fi
}

# Add a node
ng_add_node() {
  local name="$1"
  local host="$2"
  local user="${3:-root}"
  local port="${4:-22}"
  local auth="${5:-key}"
  local key="${6:-~/.ssh/id_ed25519}"
  local tags="${7:-}"

  ng_init_nodes

  # Check if jq is available
  if ! command -v jq >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "jq is required for node management. Install it first."
    else
      ng_log "ERROR" "节点管理需要 jq，请先安装。"
    fi
    return 1
  fi

  # Check if node already exists
  if jq -e ".servers[] | select(.name == \"${name}\")" "${NG_NODES_FILE}" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "Node '${name}' already exists. Use edit to modify."
    else
      ng_log "WARN" "节点 '${name}' 已存在，请使用编辑功能修改。"
    fi
    return 1
  fi

  # Add node to JSON
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

# Remove a node
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

  if ! jq -e ".servers[] | select(.name == \"${name}\")" "${NG_NODES_FILE}" >/dev/null 2>&1; then
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

# List all nodes
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

# Test SSH connection to a node
ng_test_node_ssh() {
  local name="$1"
  local host="$2"
  local user="$3"
  local port="$4"
  local auth="$5"
  local key="$6"

  local ssh_opts="-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -p ${port}"

  if [[ "${auth}" == "key" ]]; then
    ssh_opts="${ssh_opts} -i ${key}"
  fi

  if ssh ${ssh_opts} "${user}@${host}" "echo 'SSH_OK'" 2>/dev/null | grep -q "SSH_OK"; then
    return 0
  else
    return 1
  fi
}

# Test all nodes
ng_test_all_nodes() {
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
      printf 'No nodes to test.\n'
    else
      printf '没有可测试的节点。\n'
    fi
    return 0
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '%-20s %-20s %-10s\n' "NODE" "HOST" "STATUS"
    printf '%s\n' '--------------------------------------------------'
  else
    printf '%-20s %-20s %-10s\n' "节点" "主机" "状态"
    printf '%s\n' '--------------------------------------------------'
  fi

  jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null | while read -r node; do
    local name host user port auth key
    name=$(echo "${node}" | jq -r '.name')
    host=$(echo "${node}" | jq -r '.host')
    user=$(echo "${node}" | jq -r '.ssh.user // "root"')
    port=$(echo "${node}" | jq -r '.ssh.port // 22')
    auth=$(echo "${node}" | jq -r '.ssh.auth // "key"')
    key=$(echo "${node}" | jq -r '.ssh.key // "~/.ssh/id_ed25519"')

    local status
    if ng_test_node_ssh "${name}" "${host}" "${user}" "${port}" "${auth}" "${key}"; then
      status="✓ OK"
    else
      status="✗ FAIL"
    fi
    printf '%-20s %-20s %-10s\n' "${name}" "${host}" "${status}"
  done
}

# Run command on a single node
ng_run_on_node() {
  local name="$1"
  local command="$2"

  if ! command -v jq >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "jq is required."
    else
      ng_log "ERROR" "需要 jq。"
    fi
    return 1
  fi

  local node
  node=$(jq -c ".servers[] | select(.name == \"${name}\")" "${NG_NODES_FILE}" 2>/dev/null)

  if [[ -z "${node}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "Node '${name}' not found."
    else
      ng_log "ERROR" "节点 '${name}' 不存在。"
    fi
    return 1
  fi

  local host user port auth key
  host=$(echo "${node}" | jq -r '.host')
  user=$(echo "${node}" | jq -r '.ssh.user // "root"')
  port=$(echo "${node}" | jq -r '.ssh.port // 22')
  auth=$(echo "${node}" | jq -r '.ssh.auth // "key"')
  key=$(echo "${node}" | jq -r '.ssh.key // "~/.ssh/id_ed25519"')

  local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -p ${port}"
  if [[ "${auth}" == "key" ]]; then
    ssh_opts="${ssh_opts} -i ${key}"
  fi

  ssh ${ssh_opts} "${user}@${host}" "${command}" 2>&1
}

# Run command on all nodes
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

      local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -p ${port}"
      if [[ "${auth}" == "key" ]]; then
        ssh_opts="${ssh_opts} -i ${key}"
      fi

      local output status
      output=$(ssh ${ssh_opts} "${user}@${host}" "${command}" 2>&1) && status="OK" || status="FAIL"
      printf '%-20s %-10s %s\n' "${name}" "${status}" "$(echo "${output}" | head -1)"
    done
  } | tee "${output_file}"

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nResults saved to: %s\n' "${output_file}"
  else
    printf '\n结果已保存至: %s\n' "${output_file}"
  fi
}

# Sync config to all nodes
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

  jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null | while read -r node; do
    local name host user port auth key
    name=$(echo "${node}" | jq -r '.name')
    host=$(echo "${node}" | jq -r '.host')
    user=$(echo "${node}" | jq -r '.ssh.user // "root"')
    port=$(echo "${node}" | jq -r '.ssh.port // 22')
    auth=$(echo "${node}" | jq -r '.ssh.auth // "key"')
    key=$(echo "${node}" | jq -r '.ssh.key // "~/.ssh/id_ed25519"')

    local scp_opts="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -P ${port}"
    if [[ "${auth}" == "key" ]]; then
      scp_opts="${scp_opts} -i ${key}"
    fi

    if scp ${scp_opts} "${source_file}" "${user}@${host}:${remote_path}" 2>/dev/null; then
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
  done

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nSync completed: %d success, %d failed\n' "${success}" "${failed}"
  else
    printf '\n同步完成: %d 成功, %d 失败\n' "${success}" "${failed}"
  fi
}

# Node management menu
ng_node_menu() {
  local choice

  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛰 Node Management" "Multi-server management with SSH"
      ng_print_option "1" "📋" "List nodes" "Show all configured nodes"
      ng_print_option "2" "➕" "Add node" "Add a new server node"
      ng_print_option "3" "➖" "Remove node" "Remove a server node"
      ng_print_option "4" "🔍" "Test all nodes" "Test SSH connectivity to all nodes"
      ng_print_option "5" "📡" "Probe all nodes" "Check ICMP, SSH, latency and local health"
      ng_print_option "6" "⚡" "Batch execute" "Run command on all nodes"
      ng_print_option "7" "📁" "Sync config" "Sync config file to all nodes"
      ng_print_option "8" "💾" "Backup management" "Backup and restore config/state files"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛰 节点管理" "基于 SSH 的多服务器管理"
      ng_print_option "1" "📋" "列出节点" "显示所有已配置的节点"
      ng_print_option "2" "➕" "添加节点" "添加新的服务器节点"
      ng_print_option "3" "➖" "删除节点" "删除服务器节点"
      ng_print_option "4" "🔍" "测试所有节点" "测试所有节点的 SSH 连接"
      ng_print_option "5" "📡" "探测所有节点" "检查 ICMP、SSH、延迟和本机健康"
      ng_print_option "6" "⚡" "批量执行" "在所有节点上执行命令"
      ng_print_option "7" "📁" "配置同步" "将配置文件同步到所有节点"
      ng_print_option "8" "💾" "备份管理" "备份和恢复配置/状态文件"
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
            ng_read_line key || return 130
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
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter source file path: '
        else
          printf '输入源文件路径：'
        fi
        local src_file
        ng_read_line src_file || return 130

        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Enter remote target path: '
        else
          printf '输入远程目标路径：'
        fi
        local remote_path
        ng_read_line remote_path || return 130

        if [[ -n "${src_file}" && -n "${remote_path}" ]]; then
          ng_sync_to_all_nodes "${src_file}" "${remote_path}"
        fi
        ;;
      8) ng_backup_manager ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || return 130
  done
}
