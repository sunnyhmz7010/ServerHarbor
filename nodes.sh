#!/usr/bin/env bash

set -euo pipefail

NG_NODES_FILE="${NG_DATA_ROOT}/config/servers.json"

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

ng_read_nodes() {
  ng_init_nodes
  if ng_ensure_jq; then
    jq -r '.servers[] | select(.enabled != false) | "\(.name),\(.host),\(.ssh.user // "root"),\(.ssh.port // 22),\(.ssh.auth // "key"),\(.ssh.key // "~/.ssh/id_ed25519")"' "${NG_NODES_FILE}" 2>/dev/null || true
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "WARN" "jq not available, falling back to peers.conf"
    else
      ng_log "WARN" "jq 不可用，回退到 peers.conf"
    fi
    ng_read_peers
  fi
}

ng_node_count() {
  if command -v jq >/dev/null 2>&1; then
    jq '[.servers[] | select(.enabled != false)] | length' "${NG_NODES_FILE}" 2>/dev/null || echo 0
  else
    ng_read_nodes | wc -l | tr -d ' '
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
    ng_log "ERROR" "Node name is required."
    return 1
  fi

  if [[ -z "${host}" ]]; then
    ng_log "ERROR" "Host is required."
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

  if jq -e ".servers[] | select(.name == \"${name}\")" "${NG_NODES_FILE}" >/dev/null 2>&1; then
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
    echo "OK"
    return 0
  } || {
    if echo "${output}" | grep -qi "connection refused"; then
      echo "CONN_REFUSED"
    elif echo "${output}" | grep -qi "connection timed out\|no route to host"; then
      echo "TIMEOUT"
    elif echo "${output}" | grep -qi "permission denied"; then
      echo "AUTH_FAILED"
    elif echo "${output}" | grep -qi "host key verification failed"; then
      echo "KEY_MISMATCH"
    elif echo "${output}" | grep -qi "no such file\|not found"; then
      echo "KEY_NOT_FOUND"
    else
      echo "UNKNOWN"
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
  jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null | while read -r node; do
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
        detail="✓ Connected"
        status="OK"
        ;;
      CONN_REFUSED)
        detail="SSH port closed"
        status="FAIL"
        ;;
      TIMEOUT)
        detail="Connection timeout"
        status="FAIL"
        ;;
      AUTH_FAILED)
        detail="Authentication failed"
        status="FAIL"
        ;;
      KEY_MISMATCH)
        detail="Host key mismatch"
        status="FAIL"
        ;;
      KEY_NOT_FOUND)
        detail="SSH key not found"
        status="FAIL"
        ;;
      *)
        detail="Unknown error"
        status="FAIL"
        ;;
    esac

    printf '%-20s %-20s %-15s %s\n' "${node_name}" "${node_host}" "${status}" "${detail}"
  done
}

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

  local -a ssh_opts=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p "${port}")
  if [[ "${auth}" == "key" ]]; then
    ssh_opts+=(-i "${key}")
  fi

  ssh "${ssh_opts[@]}" "${user}@${host}" "${command}" 2>&1
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

  jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null | while read -r node; do
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
  done

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

  jq -c '.servers[]' "${NG_NODES_FILE}" 2>/dev/null | while read -r node; do
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
  done

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nDeployment completed: %d success, %d failed\n' "${success}" "${failed}"
  else
    printf '\n部署完成: %d 成功, %d 失败\n' "${success}" "${failed}"
  fi
}

ng_generate_join_command() {
  local main_host
  main_host=$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)

  local join_script="https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/scripts/join.sh"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Generate Join Command"
    printf 'Run this command on a new server to join this node group:\n\n'
    printf '%s\n' "$(ng_color "${NG_C_ACCENT}" "curl -fsSL ${join_script} | bash -s -- ${main_host} ${NG_DATA_ROOT} my-server-alias en")"
    printf '\n'
    printf 'The join script will automatically:\n'
    printf '  - Detect if the server is behind NAT\n'
    printf '  - Ask for public IP if needed\n'
    printf '  - Register with this server via SSH\n'
    printf '\n'
    printf 'Note: The new server needs SSH access to this server.\n'
  else
    ng_print_header "生成加入命令"
    printf '在新服务器上执行此命令加入节点组：\n\n'
    printf '%s\n' "$(ng_color "${NG_C_ACCENT}" "curl -fsSL ${join_script} | bash -s -- ${main_host} ${NG_DATA_ROOT} my-server-alias zh")"
    printf '\n'
    printf '加入脚本会自动：\n'
    printf '  - 检测服务器是否在 NAT 后面\n'
    printf '  - 如果需要，询问公网 IP\n'
    printf '  - 通过 SSH 注册到本服务器\n'
    printf '\n'
    printf '注意：新服务器需要能通过 SSH 连接到本服务器。\n'
  fi
}

ng_register_from_remote() {
  local main_host="$1"
  local data_root="$2"
  local alias="${3:-$(hostname)}"
  local remote_ip="${4:-${SSH_CLIENT%% *}}"
  local remote_user="${5:-root}"
  local remote_port="${6:-22}"

  local nodes_file="${data_root}/config/servers.json"

  if [[ ! -f "${nodes_file}" ]]; then
    mkdir -p "$(dirname "${nodes_file}")"
    cat > "${nodes_file}" <<EOF
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

  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required. Install it first."
    return 1
  fi

  if jq -e ".servers[] | select(.name == \"${alias}\")" "${nodes_file}" >/dev/null 2>&1; then
    echo "Node '${alias}' already exists."
    return 0
  fi

  local tmp_file="${nodes_file}.tmp"
  jq --arg name "${alias}" \
     --arg host "${remote_ip}" \
     --arg user "${remote_user}" \
     --arg port "${remote_port}" \
     '.servers += [{
       "name": $name,
       "host": $host,
       "ssh": {
         "user": $user,
         "port": ($port | tonumber),
         "auth": "key",
         "key": "~/.ssh/id_ed25519"
       },
       "tags": [],
       "enabled": true
     }]' "${nodes_file}" > "${tmp_file}" && mv -f "${tmp_file}" "${nodes_file}"

  echo "Node '${alias}' (${remote_ip}) registered successfully!"
}

ng_join_node() {
  local main_host="${1:-}"
  local data_root="${2:-${NG_DATA_ROOT}}"
  local alias="${3:-$(hostname)}"
  local lang="${4:-${NG_LANG}}"

  if [[ -z "${main_host}" ]]; then
    if [[ "${lang}" == "en" ]]; then
      ng_log "ERROR" "Main server host is required."
    else
      ng_log "ERROR" "需要主服务器地址。"
    fi
    return 1
  fi

  if [[ "${lang}" == "en" ]]; then
    ng_print_header "Node Join"
    printf 'Main server: %s\n' "${main_host}"
    printf 'Data root: %s\n' "${data_root}"
    printf 'Alias: %s\n\n' "${alias}"
  else
    ng_print_header "节点加入"
    printf '主服务器: %s\n' "${main_host}"
    printf '数据目录: %s\n' "${data_root}"
    printf '别名: %s\n\n' "${alias}"
  fi

  if ! ng_ensure_jq; then
    return 1
  fi

  local local_ip public_ip behind_nat=0
  local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")

  if command -v curl >/dev/null 2>&1; then
    public_ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "")
  fi

  if [[ -n "${public_ip}" ]] && [[ "${public_ip}" != "${local_ip}" ]]; then
    behind_nat=1
  fi

  if [[ "${lang}" == "en" ]]; then
    printf 'Local IP: %s\n' "${local_ip}"
    [[ -n "${public_ip}" ]] && printf 'Public IP: %s\n' "${public_ip}"
  else
    printf '本地 IP: %s\n' "${local_ip}"
    [[ -n "${public_ip}" ]] && printf '公网 IP: %s\n' "${public_ip}"
  fi

  local register_ip="${public_ip:-${local_ip}}"
  if [[ "${behind_nat}" -eq 0 ]]; then
    register_ip="${local_ip}"
  fi

  if [[ "${behind_nat}" -eq 1 ]]; then
    if [[ "${lang}" == "en" ]]; then
      printf '\n⚠️  Detected NAT environment (public IP differs from local IP)\n'
      printf 'The main server needs to reach this server via SSH.\n'
      printf 'Enter public IP (default: %s): ' "${public_ip}"
    else
      printf '\n⚠️  检测到 NAT 环境（公网 IP 与本地 IP 不同）\n'
      printf '主服务器需要通过 SSH 访问此服务器。\n'
      printf '输入公网 IP（默认: %s）: ' "${public_ip}"
    fi
    local input_ip
    ng_read_line input_ip || return 130
    register_ip="${input_ip:-${public_ip}}"
  fi

  local remote_script
  remote_script=$(cat <<REMOTE_EOF
#!/bin/bash
DATA_ROOT="\$1"
ALIAS="\$2"
REGISTER_IP="\$3"

NODES_FILE="\${DATA_ROOT}/config/servers.json"

if [[ ! -f "\${NODES_FILE}" ]]; then
  mkdir -p "\$(dirname "\${NODES_FILE}")"
  cat > "\${NODES_FILE}" <<EOF
{
  "defaults": { "ssh": { "user": "root", "port": 22, "key": "~/.ssh/id_ed25519" } },
  "servers": []
}
EOF
fi

if jq -e ".servers[] | select(.name == \\\"\${ALIAS}\\\")" "\${NODES_FILE}" >/dev/null 2>&1; then
  echo "EXISTS:\${ALIAS}"
  exit 0
fi

TMP_FILE="\${NODES_FILE}.tmp"
jq --arg name "\${ALIAS}" \\
   --arg host "\${REGISTER_IP}" \\
   '.servers += [{ "name": \$name, "host": \$host, "ssh": { "user": "root", "port": 22, "auth": "key", "key": "~/.ssh/id_ed25519" }, "tags": [], "enabled": true }]' "\${NODES_FILE}" > "\${TMP_FILE}" && mv -f "\${TMP_FILE}" "\${NODES_FILE}"

echo "OK:\${ALIAS}:\${REGISTER_IP}"
REMOTE_EOF
  )

  if [[ "${lang}" == "en" ]]; then
    printf 'Registering with main server...\n'
  else
    printf '正在注册到主服务器...\n'
  fi

  local remote_output
  remote_output=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${main_host}" "bash -s -- '${data_root}' '${alias}' '${register_ip}'" <<< "${remote_script}" 2>/dev/null) || true

  if echo "${remote_output}" | grep -q "^OK:"; then
    if [[ "${lang}" == "en" ]]; then
      printf '✓ Successfully registered with %s\n' "${main_host}"
      printf '  Node "%s" (%s) is now part of the node group.\n' "${alias}" "${register_ip}"
    else
      printf '✓ 成功注册到 %s\n' "${main_host}"
      printf '  节点 "%s" (%s) 已加入节点组。\n' "${alias}" "${register_ip}"
    fi
  elif echo "${remote_output}" | grep -q "^EXISTS:"; then
    if [[ "${lang}" == "en" ]]; then
      printf 'Node "%s" already exists.\n' "${alias}"
    else
      printf '节点 "%s" 已存在。\n' "${alias}"
    fi
  else
    if [[ "${lang}" == "en" ]]; then
      printf '✗ Failed to register via SSH.\n\n'
      printf 'Manual registration:\n'
      printf '  1. Copy this info to the main server:\n'
      printf '     Name: %s\n     Host: %s\n' "${alias}" "${register_ip}"
      printf '  2. Add via menu: [3] Node Management → [2] Add node\n'
    else
      printf '✗ 通过 SSH 注册失败。\n\n'
      printf '手动注册:\n'
      printf '  1. 将此信息复制到主服务器:\n'
      printf '     名称: %s\n     主机: %s\n' "${alias}" "${register_ip}"
      printf '  2. 通过菜单添加: [3] 节点管理 → [2] 添加节点\n'
    fi
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
    ng_log "ERROR" "Failed to write state file"
    return 1
  fi
}

ng_probe_single_peer() {
  local peer_host="$1"
  local peer_alias="$2"
  local ping_result ssh_result latency
  local ping_output

  ping_output="$(ping -c 1 -W "${NG_PROBE_TIMEOUT}" "${peer_host}" 2>/dev/null)" || true

  if [[ -n "${ping_output}" ]] && echo "${ping_output}" | grep -q "bytes from"; then
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
    printf 'Peer Alias       Peer Host                ICMP     SSH Port   Latency\n'
    printf '%s\n' '---------------------------------------------------------------------'

    if [[ -f "${NG_DATA_ROOT}/config/servers.json" ]] && command -v jq >/dev/null 2>&1; then
      jq -r '.servers[] | select(.enabled != false) | "\(.name),\(.host)"' "${NG_DATA_ROOT}/config/servers.json" 2>/dev/null | while IFS=',' read -r peer_alias peer_host; do
        [[ -n "${peer_alias}" && -n "${peer_host}" ]] || continue
        ng_probe_single_peer "${peer_host}" "${peer_alias}"
      done
    else
      while IFS=',' read -r peer_alias peer_host; do
        [[ -n "${peer_alias}" && -n "${peer_host}" ]] || continue
        ng_probe_single_peer "${peer_host}" "${peer_alias}"
      done < <(ng_read_peers)
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

ng_local_health() {
  local state_file
  state_file="$(ng_collect_local_probe)"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_report_header "Local Health Status"
    ng_report_meta "Hostname" "${NG_HOSTNAME}"
    ng_report_meta "Collected At" "$(ng_timestamp)"
    ng_report_section_start "System Info"
    ng_report_kv_styled "Uptime" "$(uptime -p 2>/dev/null || uptime)"
    ng_report_kv_styled "System Load" "$(ng_system_load)"
    ng_report_section_start "Resource Usage"
    ng_report_kv_styled "Memory" "$(free -m 2>/dev/null | awk '/Mem:/ {printf "%s/%sMB (%.1f%%)", $3, $2, $3/$2*100}' || echo unknown)"
    ng_report_kv_styled "Disk /" "$(df -h / 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}' || echo unknown)"
    ng_report_section_start "Network Ports"
    ng_report_line "Listening ports:"
    ss -lntp 2>/dev/null | sed -n '1,15p' | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_footer
    printf '\n'
    printf 'State saved to: %s\n' "${state_file}"
  else
    ng_report_header "本机健康状态"
    ng_report_meta "主机名" "${NG_HOSTNAME}"
    ng_report_meta "采集时间" "$(ng_timestamp)"
    ng_report_section_start "系统信息"
    ng_report_kv_styled "运行时长" "$(uptime -p 2>/dev/null || uptime)"
    ng_report_kv_styled "系统负载" "$(ng_system_load)"
    ng_report_section_start "资源使用"
    ng_report_kv_styled "内存" "$(free -m 2>/dev/null | awk '/Mem:/ {printf "%s/%sMB (%.1f%%)", $3, $2, $3/$2*100}' || echo unknown)"
    ng_report_kv_styled "磁盘 /" "$(df -h / 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}' || echo unknown)"
    ng_report_section_start "网络端口"
    ng_report_line "监听端口:"
    ss -lntp 2>/dev/null | sed -n '1,15p' | while IFS= read -r line; do
      ng_report_line "  ${line}"
    done
    ng_report_footer
    printf '\n'
    printf '状态已保存至: %s\n' "${state_file}"
  fi
}

ng_view_logs() {
  local log_type="$1"
  local log_file=""

  case "${log_type}" in
    auth)
      if [[ -f /var/log/auth.log ]]; then
        log_file="/var/log/auth.log"
      elif [[ -f /var/log/secure ]]; then
        log_file="/var/log/secure"
      fi
      ;;
    syslog)
      if [[ -f /var/log/syslog ]]; then
        log_file="/var/log/syslog"
      elif [[ -f /var/log/messages ]]; then
        log_file="/var/log/messages"
      fi
      ;;
    dmesg)
      log_file="dmesg"
      ;;
    *)
      if [[ "${NG_LANG}" == "en" ]]; then
        ng_log "ERROR" "Unknown log type: ${log_type}"
      else
        ng_log "ERROR" "未知日志类型: ${log_type}"
      fi
      return 1
      ;;
  esac

  if [[ "${log_type}" == "dmesg" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "Kernel Messages (dmesg)"
    else
      ng_print_header "内核消息 (dmesg)"
    fi
    dmesg | tail -50
  elif [[ -n "${log_file}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_header "Log: ${log_file}"
      printf 'Showing last 50 lines:\n\n'
    else
      ng_print_header "日志: ${log_file}"
      printf '显示最后 50 行:\n\n'
    fi
    tail -50 "${log_file}"
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_log "ERROR" "Log file not found for type: ${log_type}"
    else
      ng_log "ERROR" "未找到类型为 ${log_type} 的日志文件"
    fi
    return 1
  fi
}

ng_backup_manager() {
  local backup_dir="${NG_DATA_ROOT}/backups"
  mkdir -p "${backup_dir}"

  if [[ "${NG_LANG}" == "en" ]]; then
    ng_print_header "Backup Management"
    printf 'Backup directory: %s\n\n' "${backup_dir}"
    printf '  [1] Backup configuration files\n'
    printf '  [2] Backup state files\n'
    printf '  [3] List existing backups\n'
    printf '  [4] Restore from backup\n'
    printf '  [0] Back\n'
  else
    ng_print_header "备份管理"
    printf '备份目录: %s\n\n' "${backup_dir}"
    printf '  [1] 备份配置文件\n'
    printf '  [2] 备份状态文件\n'
    printf '  [3] 列出现有备份\n'
    printf '  [4] 从备份恢复\n'
    printf '  [0] 返回\n'
  fi

  local choice
  ng_read_line choice || return 130

  case "${choice}" in
    1)
      local backup_file="${backup_dir}/config-$(date '+%Y%m%d-%H%M%S').tar.gz"
      tar -czf "${backup_file}" -C "${NG_DATA_ROOT}" config 2>/dev/null
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Configuration backed up to: %s\n' "${backup_file}"
      else
        printf '配置已备份至: %s\n' "${backup_file}"
      fi
      ;;
    2)
      local backup_file="${backup_dir}/state-$(date '+%Y%m%d-%H%M%S').tar.gz"
      tar -czf "${backup_file}" -C "${NG_DATA_ROOT}" state 2>/dev/null
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'State files backed up to: %s\n' "${backup_file}"
      else
        printf '状态文件已备份至: %s\n' "${backup_file}"
      fi
      ;;
    3)
      if [[ "${NG_LANG}" == "en" ]]; then
        ng_print_header "Existing Backups"
        ls -lh "${backup_dir}"/*.tar.gz 2>/dev/null || printf 'No backups found.\n'
      else
        ng_print_header "现有备份"
        ls -lh "${backup_dir}"/*.tar.gz 2>/dev/null || printf '未找到备份文件。\n'
      fi
      ;;
    4)
      if [[ "${NG_LANG}" == "en" ]]; then
        printf 'Available backups:\n'
        ls -1 "${backup_dir}"/*.tar.gz 2>/dev/null || printf 'No backups found.\n'
        printf '\nEnter backup file path to restore: '
      else
        printf '可用备份:\n'
        ls -1 "${backup_dir}"/*.tar.gz 2>/dev/null || printf '未找到备份文件。\n'
        printf '\n输入要恢复的备份文件路径: '
      fi
      local restore_file
      ng_read_line restore_file || return 130

      if [[ -f "${restore_file}" ]]; then
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Restoring from: %s\n' "${restore_file}"
        else
          printf '正在从 %s 恢复\n' "${restore_file}"
        fi
        tar -xzf "${restore_file}" -C "${NG_DATA_ROOT}" 2>/dev/null
        if [[ "${NG_LANG}" == "en" ]]; then
          printf 'Restore completed.\n'
        else
          printf '恢复完成。\n'
        fi
      else
        if [[ "${NG_LANG}" == "en" ]]; then
          ng_log "ERROR" "Backup file not found: ${restore_file}"
        else
          ng_log "ERROR" "备份文件不存在: ${restore_file}"
        fi
      fi
      ;;
    0) return 0 ;;
    *)
      ng_t invalid_option
      ;;
  esac
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
      ng_print_option "4" "🔍" "Test all nodes" "Test SSH connectivity to all nodes"
      ng_print_option "5" "📡" "Probe all nodes" "Check ICMP, SSH, latency and local health"
      ng_print_option "6" "⚡" "Batch execute" "Run command on all nodes"
      ng_print_option "7" "📁" "Sync config" "Sync config file to all nodes"
      ng_print_option "8" "🔑" "Deploy SSH keys" "Deploy SSH keys to all nodes"
      ng_print_option "9" "🔗" "Generate join command" "Generate command for new servers to join"
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
      ng_print_option "8" "🔑" "部署 SSH 密钥" "部署 SSH 密钥到所有节点"
      ng_print_option "9" "🔗" "生成加入命令" "生成新服务器加入的命令"
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
      8) ng_deploy_ssh_keys ;;
      9) ng_generate_join_command ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || return 130
  done
}
