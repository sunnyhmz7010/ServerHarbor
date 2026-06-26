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


ng_check_node_status() {
  local host="$1"
  local port="${2:-22}"

  if ping -c 1 -W 2 "${host}" >/dev/null 2>&1; then
    if nc -z -w 2 "${host}" "${port}" 2>/dev/null; then
      if [[ "${NG_LANG}" == "en" ]]; then printf '%s' "Connected"; else printf '%s' "连通"; fi
    else
      if [[ "${NG_LANG}" == "en" ]]; then printf '%s' "SSH Down"; else printf '%s' "SSH不通"; fi
    fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then printf '%s' "Unreachable"; else printf '%s' "不可达"; fi
  fi
}

ng_setup_mutual_nodes() {
  local remote_ip ssh_port ssh_user auth_method key

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Enter remote server IP: '
  else
    printf '输入对方服务器 IP：'
  fi
  ng_read_line remote_ip || return 130
  if [[ -z "${remote_ip}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then ng_log "ERROR" "IP is required."; else ng_log "ERROR" "IP 不能为空。"; fi
    return 1
  fi

  if [[ "${NG_LANG}" == "en" ]]; then printf 'SSH port (default 22): '; else printf 'SSH 端口（默认 22）：'; fi
  ng_read_line ssh_port || return 130
  ssh_port="${ssh_port:-22}"

  if [[ "${NG_LANG}" == "en" ]]; then printf 'SSH user (default root): '; else printf 'SSH 用户（默认 root）：'; fi
  ng_read_line ssh_user || return 130
  ssh_user="${ssh_user:-root}"

  if [[ "${NG_LANG}" == "en" ]]; then
    printf 'Authentication method:\n  [1] SSH key [2] Password: '
  else
    printf '认证方式：\n  [1] SSH 密钥 [2] 密码：'
  fi
  local auth_choice
  ng_read_line auth_choice || return 130

  local -a ssh_opts=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "${ssh_port}")

  case "${auth_choice}" in
    2)
      auth_method="password"
      if [[ "${NG_LANG}" == "en" ]]; then printf 'Enter password: '; else printf '输入密码：'; fi
      IFS= read -rs key < /dev/tty
      printf '\n'
      if ! command -v sshpass >/dev/null 2>&1; then
        if [[ "${EUID}" -eq 0 ]]; then
          if command -v apt-get >/dev/null 2>&1; then apt-get install -y -qq sshpass 2>/dev/null || true
          elif command -v yum >/dev/null 2>&1; then yum install -y sshpass 2>/dev/null || true
          elif command -v dnf >/dev/null 2>&1; then dnf install -y sshpass 2>/dev/null || true
          fi
        fi
      fi
      ;;
    *)
      auth_method="key"
      local -a available_keys=()
      for kf in ~/.ssh/id_ed25519 ~/.ssh/id_rsa ~/.ssh/id_ecdsa ~/.ssh/id_dsa; do
        [[ -f "${kf}" ]] && available_keys+=("${kf}")
      done
      if [[ "${#available_keys[@]}" -eq 0 ]]; then
        if [[ "${NG_LANG}" == "en" ]]; then printf 'No SSH keys found. Generate one first.\n'; else printf '未找到 SSH 密钥，请先生成。\n'; fi
        return 1
      fi
      if [[ "${#available_keys[@]}" -eq 1 ]]; then
        key="${available_keys[0]}"
      else
        if [[ "${NG_LANG}" == "en" ]]; then printf 'Available SSH keys:\n'; else printf '可用 SSH 密钥：\n'; fi
        local ki=1; for kf in "${available_keys[@]}"; do printf '  [%d] %s\n' "${ki}" "${kf}"; ((ki++)) || true; done
        if [[ "${NG_LANG}" == "en" ]]; then printf 'Select key (default 1): '; else printf '选择密钥（默认 1）：'; fi
        local key_choice; ng_read_line key_choice || return 130; key_choice="${key_choice:-1}"
        if [[ "${key_choice}" =~ ^[0-9]+$ ]] && [[ "${key_choice}" -ge 1 ]] && [[ "${key_choice}" -le "${#available_keys[@]}" ]]; then
          key="${available_keys[$((key_choice-1))]}"
        else
          key="${available_keys[0]}"
        fi
      fi
      ;;
  esac

  local -a run_ssh=()
  if [[ "${auth_method}" == "password" ]] && command -v sshpass >/dev/null 2>&1; then
    export SSHPASS="${key}"
    run_ssh=(sshpass -e ssh "${ssh_opts[@]}" "${ssh_user}@${remote_ip}")
  else
    ssh_opts+=(-i "${key}")
    run_ssh=(ssh "${ssh_opts[@]}" "${ssh_user}@${remote_ip}")
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\n[1/4] Testing SSH to %s ...\n' "${remote_ip}"
  else
    printf '\n[1/4] 测试 SSH 连接 %s ...\n' "${remote_ip}"
  fi
  if ! "${run_ssh[@]}" "echo OK" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then ng_log "ERROR" "SSH connection failed."; else ng_log "ERROR" "SSH 连接失败。"; fi
    return 1
  fi
  if [[ "${NG_LANG}" == "en" ]]; then printf '  ✓ SSH connected\n'; else printf '  ✓ SSH 连接成功\n'; fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '[2/4] Registering remote as local node ...\n'
  else
    printf '[2/4] 注册对方为本机节点 ...\n'
  fi
  local remote_alias
  remote_alias=$("${run_ssh[@]}" "hostname" 2>/dev/null || echo "node-${remote_ip##*.}")
  remote_alias=$(echo "${remote_alias}" | tr -d '\r\n')
  ng_init_nodes
  if ! ng_ensure_jq; then return 1; fi

  if ! jq -e --arg n "${remote_alias}" '.servers[] | select(.name == $n)' "${NG_NODES_FILE}" >/dev/null 2>&1; then
    local tmp="${NG_NODES_FILE}.tmp"
    jq --arg name "${remote_alias}" --arg host "${remote_ip}" --arg user "${ssh_user}" --arg port "${ssh_port}" --arg auth "${auth_method}" --arg key "${key}" \
      '.servers += [{name:$name,host:$host,ssh:{user:$user,port:($port|number),auth:$auth,key:$key},tags:[],enabled:true}]' \
      "${NG_NODES_FILE}" > "${tmp}" && mv -f "${tmp}" "${NG_NODES_FILE}"
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ✓ Node "%s" added\n' "${remote_alias}"; else printf '  ✓ 节点 "%s" 已添加\n' "${remote_alias}"; fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ⚠ Node "%s" already exists\n' "${remote_alias}"; else printf '  ⚠ 节点 "%s" 已存在\n' "${remote_alias}"; fi
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '[3/4] Registering self on remote server ...\n'
  else
    printf '[3/4] 在对方服务器上注册本机 ...\n'
  fi
  local my_ip
  my_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)
  local my_alias="${NG_HOSTNAME}"

  local remote_nodes_file
  remote_nodes_file=$("${run_ssh[@]}" "bash -c 'echo \${SERVERHARBOR_HOME:-\${XDG_CONFIG_HOME:-\$HOME/.config}/serverharbor}/servers.json'" 2>/dev/null || echo "")
  remote_nodes_file=$(echo "${remote_nodes_file}" | tr -d '\r\n')
  if [[ -z "${remote_nodes_file}" ]]; then
    remote_nodes_file="~/.config/serverharbor/servers.json"
  fi

  local register_cmd="mkdir -p \$(dirname ${remote_nodes_file}) && [[ -f ${remote_nodes_file} ]] || cat > ${remote_nodes_file} <<'EOFCFG'
{\"defaults\":{\"ssh\":{\"user\":\"root\",\"port\":22,\"key\":\"~/.ssh/id_ed25519\"}},\"servers\":[]}
EOFCFG
jq --arg name '${my_alias}' --arg host '${my_ip}' --arg user 'root' --arg port '22' --arg auth 'key' --arg key '~/.ssh/id_ed25519' '.servers += [{name:\$name,host:\$host,ssh:{user:\$user,port:(\$port|number),auth:\$auth,key:\$key},tags:[],enabled:true}]' ${remote_nodes_file} > ${remote_nodes_file}.tmp && mv -f ${remote_nodes_file}.tmp ${remote_nodes_file}"

  if "${run_ssh[@]}" "bash -c '${register_cmd}'" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ✓ Self registered on remote\n'; else printf '  ✓ 本机已注册到对方服务器\n'; fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ✗ Failed to register on remote\n'; else printf '  ✗ 在对方服务器注册失败\n'; fi
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '[4/4] Verifying bidirectional connectivity ...\n'
  else
    printf '[4/4] 验证双向连通性 ...\n'
  fi

  local ok_a=0 ok_b=0
  if "${run_ssh[@]}" "ping -c 1 -W 2 ${my_ip}" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ✓ Remote → Local: Connected\n'; else printf '  ✓ 对方 → 本机：连通\n'; fi
    ok_a=1
  else
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ✗ Remote → Local: Unreachable\n'; else printf '  ✗ 对方 → 本机：不可达\n'; fi
  fi

  if ping -c 1 -W 2 "${remote_ip}" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ✓ Local → Remote: Connected\n'; else printf '  ✓ 本机 → 对方：连通\n'; fi
    ok_b=1
  else
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ✗ Local → Remote: Unreachable\n'; else printf '  ✗ 本机 → 对方：不可达\n'; fi
  fi

  if [[ "${ok_a}" -eq 1 ]] && [[ "${ok_b}" -eq 1 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\n✓ Mutual trust established!\n'
      printf '  Local (%s) ↔ Remote (%s)\n' "${my_ip}" "${remote_ip}"
    else
      printf '\n✓ 互信节点建立完成！\n'
      printf '  本机 (%s) ↔ 对方 (%s)\n' "${my_ip}" "${remote_ip}"
    fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '\n⚠ Partial connectivity. Check firewall/security groups.\n'
    else
      printf '\n⚠ 部分连通，请检查防火墙/安全组设置。\n'
    fi
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
    local -a node_ports=()
    local idx=1

    if command -v jq >/dev/null 2>&1 && [[ -f "${NG_NODES_FILE}" ]]; then
      while IFS=$'\t' read -r name host port; do
        local node_status
        node_status=$(ng_check_node_status "${host}" "${port}")
        printf '  [%d] %-20s %-20s %s\n' "${idx}" "${name}" "${host}" "${node_status}"
        node_names+=("${name}")
        node_hosts+=("${host}")
        node_ports+=("${port}")
        ((idx++)) || true
      done < <(jq -r '.servers[] | select(.enabled != false) | "\(.name)\t\(.host)\t\(.ssh.port // 22)"' "${NG_NODES_FILE}" 2>/dev/null)
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
        if [[ "${NG_LANG}" == "en" ]]; then
          printf '\n⚠️  Registration only records node info locally.\n'
          printf '   No software is installed or modified on the remote server.\n\n'
        else
          printf '\n⚠️  注册仅在本地记录节点信息，\n'
          printf '   不会在远程服务器上安装或修改任何内容。\n\n'
        fi

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
            if export SSHPASS="${key}" && sshpass -e ssh "${test_opts[@]}" "${user}@${host}" "echo OK" >/dev/null 2>&1; then
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

ng_remote_execute() {
  if ! ng_ensure_jq; then return 1; fi
  if [[ ! -f "${NG_NODES_FILE}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No nodes configured.\n'; else printf '未配置节点。\n'; fi
    return 1
  fi

  local count
  count=$(jq '.servers | length' "${NG_NODES_FILE}" 2>/dev/null || echo "0")
  count=$(echo "${count}" | tr -d '[:space:]')
  : "${count:=0}"
  if [[ "${count}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No nodes configured.\n'; else printf '未配置节点。\n'; fi
    return 1
  fi

  if [[ "${NG_LANG}" == "en" ]]; then printf '\nSelect target node:\n'; else printf '\n选择目标节点：\n'; fi
  local idx=1
  local -a node_names=()
  while IFS=$'\t' read -r name host; do
    local node_status
    node_status=$(ng_check_node_status "${host}")
    printf '  [%d] %-20s %-20s %s\n' "${idx}" "${name}" "${host}" "${node_status}"
    node_names+=("${name}")
    ((idx++)) || true
  done < <(jq -r '.servers[] | select(.enabled != false) | "\(.name)\t\(.host)"' "${NG_NODES_FILE}" 2>/dev/null)

  printf '\n'
  if [[ "${NG_LANG}" == "en" ]]; then printf 'Select node (number): '; else printf '选择节点（输入编号）：'; fi
  local sel
  ng_read_line sel || return 130

  if [[ -z "${sel}" ]] || ! [[ "${sel}" =~ ^[0-9]+$ ]] || [[ "${sel}" -lt 1 ]] || [[ "${sel}" -gt "${idx}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'Invalid selection.\n'; else printf '无效选择。\n'; fi
    return 0
  fi

  local node_name="${node_names[$((sel-1))]}"
  local node_host node_user node_port node_auth node_key
  node_host=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .host' "${NG_NODES_FILE}" 2>/dev/null)
  node_user=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.user // "root"' "${NG_NODES_FILE}" 2>/dev/null)
  node_port=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.port // 22' "${NG_NODES_FILE}" 2>/dev/null)
  node_auth=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.auth // "key"' "${NG_NODES_FILE}" 2>/dev/null)
  node_key=$(jq -r --arg n "${node_name}" '.servers[] | select(.name == $n) | .ssh.key // "~/.ssh/id_ed25519"' "${NG_NODES_FILE}" 2>/dev/null)

  if [[ -z "${node_host}" || "${node_host}" == "null" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then ng_log "ERROR" "Node not found."; else ng_log "ERROR" "节点不存在。"; fi
    return 1
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nRemote execute on %s (%s):\n' "${node_name}" "${node_host}"
    printf '  [1] Custom command\n'
    printf '  [2] Install base packages (curl, wget, sudo, iptables)\n'
    printf '  [3] Install Docker\n'
    printf '  [4] bbrv3-lite network tuning\n'
    printf '  [5] vps-tcp-tune network tuning\n'
    printf '  [6] System status\n'
    printf '  [0] Cancel\n'
  else
    printf '\n在 %s (%s) 上远程执行：\n' "${node_name}" "${node_host}"
    printf '  [1] 自定义命令\n'
    printf '  [2] 基础软件安装（curl、wget、sudo、iptables）\n'
    printf '  [3] Docker 安装\n'
    printf '  [4] bbrv3-lite 网络调优\n'
    printf '  [5] vps-tcp-tune 网络调优\n'
    printf '  [6] 系统状态查看\n'
    printf '  [0] 取消\n'
  fi

  printf '\n'
  ng_t select
  local op_choice
  ng_read_line op_choice || return 130

  local -a ssh_opts=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p "${node_port}")
  local use_sshpass=0

  if [[ "${node_auth}" == "password" ]] && command -v sshpass >/dev/null 2>&1; then
    use_sshpass=1
    export SSHPASS="${node_key}"
  else
    ssh_opts+=(-i "${node_key}")
  fi

  local cmd=""

  case "${op_choice}" in
    1)
      if [[ "${NG_LANG}" == "en" ]]; then printf 'Enter command: '; else printf '输入命令：'; fi
      ng_read_line cmd || return 130
      ;;
    2)
      cmd="apt-get update -y && apt-get install -y curl wget sudo iptables || yum install -y curl wget sudo iptables"
      ;;
    3)
      local country
      country=$("${run_ssh[@]}" "curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null" || echo "unknown")
      country=$(echo "${country}" | tr -d '\r\n')
      if [[ "${country}" == "CN" ]]; then
        cmd="curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun"
      else
        cmd="curl -fsSL https://get.docker.com | sh"
      fi
      ;;
    4)
      cmd="bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/bbrv3-lite/main/net-tcp-tune.sh)"
      ;;
    5)
      cmd="bash <(curl -fsSL https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh)"
      ;;
    6)
      cmd="echo '=== System Info ==='; hostname; uname -r; uptime; echo ''; echo '=== CPU ==='; nproc; grep 'model name' /proc/cpuinfo | head -1; echo ''; echo '=== Memory ==='; free -h; echo ''; echo '=== Disk ==='; df -h /; echo ''; echo '=== Network ==='; hostname -I; echo ''; echo '=== Docker ==='; docker --version 2>/dev/null || echo 'Not installed'"
      ;;
    0) return 0 ;;
    *)
      ng_t invalid_option
      return 0
      ;;
  esac

  if [[ -z "${cmd}" ]]; then
    return 1
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\nExecuting on %s ...\n\n' "${node_name}"
  else
    printf '\n正在 %s 上执行 ...\n\n' "${node_name}"
  fi

  if [[ "${use_sshpass}" -eq 1 ]]; then
    sshpass -e ssh "${ssh_opts[@]}" "${node_user}@${node_host}" "bash -c '${cmd}'"
  else
    ssh "${ssh_opts[@]}" "${node_user}@${node_host}" "bash -c '${cmd}'"
  fi
  local rc=$?

  printf '\n'
  if [[ "${rc}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '✓ Completed on %s\n' "${node_name}"
    else
      printf '✓ %s 执行完成\n' "${node_name}"
    fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then
      printf '✗ Failed on %s (exit code: %d)\n' "${node_name}" "${rc}"
    else
      printf '✗ %s 执行失败（退出码: %d）\n' "${node_name}" "${rc}"
    fi
  fi
}

ng_node_menu() {
  local choice

  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛰 Node Management" "Multi-server management with SSH"
      ng_print_option "1" "📋" "Node list" "List / add / remove nodes"
      ng_print_option "2" "🤝" "Setup mutual" "Bidirectional node registration"
      ng_print_option "3" "🚀" "Remote execute" "Run commands or presets on a node"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛰 节点管理" "基于 SSH 的多服务器管理"
      ng_print_option "1" "📋" "节点列表" "列出 / 添加 / 删除节点"
      ng_print_option "2" "🤝" "建立互信" "双向注册，两台服务器互为节点"
      ng_print_option "3" "🚀" "远程执行" "在选中节点上执行命令或预设操作"
      ng_print_option "0" "↩" "返回"
    fi

    printf '\n'
    ng_print_menu_hint
    printf '\n'
    ng_t select
    ng_read_line choice || return 130

    case "${choice}" in
      1) ng_node_manage ;;
      2) ng_setup_mutual_nodes ;;
      3) ng_remote_execute ;;
      0) return 0 ;;
      *) ng_t invalid_option ;;
    esac

    ng_press_enter || return 130
  done
}
