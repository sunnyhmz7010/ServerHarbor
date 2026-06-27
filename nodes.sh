#!/usr/bin/env bash

set -euo pipefail

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
  if ! [[ -f "${NG_CONFIG_FILE}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No config found. Add a node first.\n'; else printf '未找到配置，请先添加节点。\n'; fi
    return 0
  fi

  local -a node_lines=()
  while IFS= read -r line; do
    line=$(printf '%s' "${line}" | tr -d '\r')
    [[ -n "${line}" ]] && node_lines+=("${line}")
  done < <(ng_get_nodes)

  if [[ "${#node_lines[@]}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No nodes configured. Add a node first.\n'; else printf '未配置节点，请先添加节点。\n'; fi
    return 0
  fi

  if [[ "${NG_LANG}" == "en" ]]; then printf '\nSelect a node for mutual trust:\n'; else printf '\n选择要建立互信的节点：\n'; fi
  local ni=1
  local -a existing_names=()
  local -a existing_hosts=()
  local -a existing_ports=()
  local -a existing_users=()
  local -a existing_auths=()
  local -a existing_keys=()

  for line in "${node_lines[@]}"; do
    local n h p au a k
    n=$(printf '%s' "${line}" | cut -f1)
    h=$(printf '%s' "${line}" | cut -f2)
    p=$(printf '%s' "${line}" | cut -f3)
    au=$(printf '%s' "${line}" | cut -f4)
    a=$(printf '%s' "${line}" | cut -f5)
    k=$(printf '%s' "${line}" | cut -f6)
    [[ -z "${n}" || "${n}" == "#"* ]] && continue
    local node_status
    node_status=$(ng_check_node_status "${h}" "${p}")
    printf '  [%d] %-20s %-20s %s\n' "${ni}" "${n}" "${h}" "${node_status}"
    existing_names+=("${n}")
    existing_hosts+=("${h}")
    existing_ports+=("${p}")
    existing_users+=("${au}")
    existing_auths+=("${a}")
    existing_keys+=("${k}")
    ((ni++)) || true
  done
  printf '  [0] %s\n' "$( [[ "${NG_LANG}" == "en" ]] && echo "Back" || echo "返回" )"

  printf '\n'
  if [[ "${NG_LANG}" == "en" ]]; then printf 'Select: '; else printf '选择：'; fi
  local node_sel
  ng_read_line node_sel || return 130

  [[ "${node_sel}" == "0" ]] && return 0

  if [[ -z "${node_sel}" ]] || ! [[ "${node_sel}" =~ ^[0-9]+$ ]] || [[ "${node_sel}" -lt 1 ]] || [[ "${node_sel}" -ge "${ni}" ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'Invalid selection.\n'; else printf '无效选择。\n'; fi
    return 0
  fi

  local sel_name="${existing_names[$((node_sel-1))]}"
  local remote_ip="${existing_hosts[$((node_sel-1))]}"
  local ssh_port="${existing_ports[$((node_sel-1))]}"
  local ssh_user="${existing_users[$((node_sel-1))]}"
  local auth_method="${existing_auths[$((node_sel-1))]}"
  local key="${existing_keys[$((node_sel-1))]}"

  local -a ssh_opts=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "${ssh_port}")
  local use_sshpass=0

  if [[ "${auth_method}" == "password" ]] && command -v sshpass >/dev/null 2>&1; then
    use_sshpass=1
    export SSHPASS="${key}"
  else
    ssh_opts+=(-i "${key}")
  fi

  local -a run_ssh=()
  if [[ "${use_sshpass}" -eq 1 ]]; then
    run_ssh=(sshpass -e ssh "${ssh_opts[@]}" "${ssh_user}@${remote_ip}")
  else
    run_ssh=(ssh "${ssh_opts[@]}" "${ssh_user}@${remote_ip}")
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '\n[1/3] Testing SSH to %s ...\n' "${remote_ip}"
  else
    printf '\n[1/3] 测试 SSH 连接 %s ...\n' "${remote_ip}"
  fi
  if ! "${run_ssh[@]}" "echo OK" >/dev/null 2>&1; then
    if [[ "${NG_LANG}" == "en" ]]; then ng_log "ERROR" "SSH connection failed."; else ng_log "ERROR" "SSH 连接失败。"; fi
    return 1
  fi
  if [[ "${NG_LANG}" == "en" ]]; then printf '  ✓ SSH connected\n'; else printf '  ✓ SSH 连接成功\n'; fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '[2/3] Registering self on remote server ...\n'
  else
    printf '[2/3] 在对方服务器上注册本机 ...\n'
  fi
  local my_ip
  my_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)
  local my_alias="${NG_HOSTNAME}"

  local remote_conf
  remote_conf=$("${run_ssh[@]}" "bash -c 'if [ -f /opt/serverharbor/.serverharbor-install ]; then echo /opt/serverharbor/data/serverharbor.conf; else echo \${XDG_CONFIG_HOME:-\$HOME/.config}/serverharbor/serverharbor.conf; fi'" 2>/dev/null || echo "")
  remote_conf=$(echo "${remote_conf}" | tr -d '\r\n')
  if [[ -z "${remote_conf}" ]]; then
    remote_conf="~/.config/serverharbor/serverharbor.conf"
  fi

  local remote_line="${my_alias}	${my_ip}	${ssh_port}	${ssh_user}	${auth_method}	${key}	true"

  local register_cmd="mkdir -p \$(dirname ${remote_conf}) && [[ -f ${remote_conf} ]] || printf '# ServerHarbor Configuration\n\n__NODES__\n__NODES__\n' > ${remote_conf}"
  register_cmd="${register_cmd} && if grep -q '^${my_alias}	' ${remote_conf} 2>/dev/null; then echo EXISTS; else"
  register_cmd="${register_cmd} tmp=\${remote_conf}.tmp"
  register_cmd="${register_cmd} && sed '/^__NODES__$/,\$d' ${remote_conf} > \${tmp}"
  register_cmd="${register_cmd} && existing=\$(sed -n '/^__NODES__$/,/^__NODES__\$/{ /^__NODES__\$/d; p; }' ${remote_conf} 2>/dev/null)"
  register_cmd="${register_cmd} && { cat \${tmp}; printf '%s\n' '__NODES__';"
  register_cmd="${register_cmd} if [ -n \"\${existing}\" ]; then printf '%s\n' \"\${existing}\"; fi;"
  register_cmd="${register_cmd} printf '%s\n' '${my_alias}	${my_ip}	${ssh_port}	${ssh_user}	${auth_method}	${key}	true';"
  register_cmd="${register_cmd} printf '%s\n' '__NODES__'; } > ${remote_conf}"
  register_cmd="${register_cmd} && rm -f \${tmp}"
  register_cmd="${register_cmd} && echo OK; fi"

  local remote_output
  remote_output=$("${run_ssh[@]}" "bash -c '${register_cmd}'" 2>&1) || true

  if echo "${remote_output}" | grep -q "^OK"; then
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ✓ Self registered on remote\n'; else printf '  ✓ 本机已注册到对方服务器\n'; fi
  elif echo "${remote_output}" | grep -q "^EXISTS"; then
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ⚠ Already registered on remote\n'; else printf '  ⚠ 已在对方服务器注册过\n'; fi
  else
    if [[ "${NG_LANG}" == "en" ]]; then printf '  ✗ Failed to register on remote\n'; else printf '  ✗ 在对方服务器注册失败\n'; fi
  fi

  if [[ "${NG_LANG}" == "en" ]]; then
    printf '[3/3] Verifying bidirectional connectivity ...\n'
  else
    printf '[3/3] 验证双向连通性 ...\n'
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

    local -a node_lines=()
    while IFS= read -r line; do
      line=$(printf '%s' "${line}" | tr -d '\r')
      [[ -n "${line}" ]] && node_lines+=("${line}")
    done < <(ng_get_nodes)

    for line in "${node_lines[@]}"; do
      local n h p e
      n=$(printf '%s' "${line}" | cut -f1)
      h=$(printf '%s' "${line}" | cut -f2)
      p=$(printf '%s' "${line}" | cut -f3)
      e=$(printf '%s' "${line}" | cut -f6)
      [[ -z "${n}" || "${n}" == "#"* ]] && continue
      [[ "${e}" == "true" ]] || continue
      local node_status
      node_status=$(ng_check_node_status "${h}" "${p}")
      printf '  [%d] %-20s %-20s %s\n' "${idx}" "${n}" "${h}" "${node_status}"
      node_names+=("${n}")
      node_hosts+=("${h}")
      node_ports+=("${p}")
      ((idx++)) || true
    done

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
        printf '  [1-%d] Edit or remove node by number\n' "$((idx-1))"
      fi
      printf '  [0] Back\n'
    else
      printf '  [a] 添加节点\n'
      if [[ "${idx}" -gt 1 ]]; then
        printf '  [1-%d] 输入序号编辑或删除节点\n' "$((idx-1))"
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
          local existing
          existing=$(ng_get_nodes | grep "^${alias}	" || true)
          if [[ -n "${existing}" ]]; then
            if [[ "${NG_LANG}" == "en" ]]; then
              printf 'Node "%s" already exists.\n' "${alias}"
            else
              printf '节点 "%s" 已存在。\n' "${alias}"
            fi
          else
            if [[ "${NG_LANG}" == "en" ]]; then
              printf '\nTesting SSH %s@%s:%s ...\n' "${user}" "${host}" "${port}"
            else
              printf '\n正在测试 SSH 连接 %s@%s:%s ...\n' "${user}" "${host}" "${port}"
            fi

            local -a test_opts=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "${port}")
            local ssh_ok=0

            if [[ "${auth}" == "password" ]]; then
              if command -v sshpass >/dev/null 2>&1; then
                SSHPASS="${key}" sshpass -e ssh "${test_opts[@]}" "${user}@${host}" "echo OK" >/dev/null 2>&1 && ssh_ok=1
              fi
            else
              test_opts+=(-i "${key}")
              ssh "${test_opts[@]}" "${user}@${host}" "echo OK" >/dev/null 2>&1 && ssh_ok=1
            fi

            if [[ "${ssh_ok}" -eq 1 ]]; then
              if [[ "${NG_LANG}" == "en" ]]; then
                printf '✓ SSH connected.\n'
              else
                printf '✓ SSH 连接成功。\n'
              fi
              ng_add_node_to_file "${alias}	${host}	${port}	${user}	${auth}	${key}	true"
              if [[ "${NG_LANG}" == "en" ]]; then
                printf '✓ Node "%s" added.\n' "${alias}"
              else
                printf '✓ 节点 "%s" 已添加。\n' "${alias}"
              fi
            else
              if [[ "${NG_LANG}" == "en" ]]; then
                printf '✗ SSH failed. Node not added.\n'
              else
                printf '✗ SSH 连接失败，节点未添加。\n'
              fi
            fi
          fi
        fi
        ng_press_enter || return 130
        ;;

      *)
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -lt "${idx}" ]]; then
          local target_name="${node_names[$((choice-1))]}"
          local target_host="${node_hosts[$((choice-1))]}"

          if [[ "${NG_LANG}" == "en" ]]; then
            printf '\nNode: %s (%s)\n' "${target_name}" "${target_host}"
            printf '  [e] Edit name\n'
            printf '  [d] Delete\n'
            printf '  [0] Cancel\n'
            printf 'Note: To change IP, port, user, or auth, delete and re-add.\n'
            printf 'Choose: '
          else
            printf '\n节点: %s (%s)\n' "${target_name}" "${target_host}"
            printf '  [e] 修改名称\n'
            printf '  [d] 删除\n'
            printf '  [0] 取消\n'
            printf '提示：如需修改 IP、端口、用户或认证方式，请删除节点后重新添加。\n'
            printf '选择：'
          fi
          local action
          ng_read_line action || return 130

          case "${action}" in
            e|E)
              if [[ "${NG_LANG}" == "en" ]]; then
                printf 'New name (current: %s): ' "${target_name}"
              else
                printf '新名称（当前: %s）：' "${target_name}"
              fi
              local new_name
              ng_read_line new_name || return 130
              if [[ -n "${new_name}" && "${new_name}" != "${target_name}" ]]; then
                ng_rename_node_in_file "${target_name}" "${new_name}"
                if [[ "${NG_LANG}" == "en" ]]; then
                  printf '✓ Renamed "%s" → "%s"\n' "${target_name}" "${new_name}"
                else
                  printf '✓ 已重命名 "%s" → "%s"\n' "${target_name}" "${new_name}"
                fi
              fi
              ;;
            d|D)
              if [[ "${NG_LANG}" == "en" ]]; then
                printf 'Remove node "%s"? [y/N]: ' "${target_name}"
              else
                printf '删除节点 "%s"？[y/N]：' "${target_name}"
              fi
              local confirm
              ng_read_line confirm || return 130
              if [[ "${confirm}" =~ ^[Yy] ]]; then
                ng_remove_node_from_file "${target_name}"
                if [[ "${NG_LANG}" == "en" ]]; then
                  printf '✓ Node "%s" removed.\n' "${target_name}"
                else
                  printf '✓ 节点 "%s" 已删除。\n' "${target_name}"
                fi
              fi
              ;;
            0|"") ;;
            *) ng_t invalid_option ;;
          esac
        else
          ng_t invalid_option
        fi
        ng_press_enter || return 130
        ;;
    esac
  done
}

ng_remote_execute() {
  local -a node_lines=()
  while IFS= read -r line; do
    line=$(printf '%s' "${line}" | tr -d '\r')
    [[ -n "${line}" ]] && node_lines+=("${line}")
  done < <(ng_get_nodes)

  if [[ "${#node_lines[@]}" -eq 0 ]]; then
    if [[ "${NG_LANG}" == "en" ]]; then printf 'No nodes configured.\n'; else printf '未配置节点。\n'; fi
    return 1
  fi

  export TERM=xterm

  while true; do
    if [[ "${NG_LANG}" == "en" ]]; then printf '\nSelect target node:\n'; else printf '\n选择目标节点：\n'; fi
    local idx=1
    local -a node_names=()
    local -a node_hosts=()
    local -a node_ports=()
    local -a node_users=()
    local -a node_auths=()
    local -a node_keys=()

    for line in "${node_lines[@]}"; do
      local n h p au a k
      n=$(printf '%s' "${line}" | cut -f1)
      h=$(printf '%s' "${line}" | cut -f2)
      p=$(printf '%s' "${line}" | cut -f3)
      au=$(printf '%s' "${line}" | cut -f4)
      a=$(printf '%s' "${line}" | cut -f5)
      k=$(printf '%s' "${line}" | cut -f6)
      [[ -z "${n}" || "${n}" == "#"* ]] && continue
      local node_status
      node_status=$(ng_check_node_status "${h}" "${p}")
      printf '  [%d] %-20s %-20s %s\n' "${idx}" "${n}" "${h}" "${node_status}"
      node_names+=("${n}")
      node_hosts+=("${h}")
      node_ports+=("${p}")
      node_users+=("${au}")
      node_auths+=("${a}")
      node_keys+=("${k}")
      ((idx++)) || true
    done
    printf '  [0] %s\n' "$( [[ "${NG_LANG}" == "en" ]] && echo "Back" || echo "返回" )"

    printf '\n'
    if [[ "${NG_LANG}" == "en" ]]; then printf 'Select node (number): '; else printf '选择节点（输入编号）：'; fi
    local sel
    ng_read_line sel || return 130

    [[ "${sel}" == "0" ]] && return 0

    if [[ -z "${sel}" ]] || ! [[ "${sel}" =~ ^[0-9]+$ ]] || [[ "${sel}" -lt 1 ]] || [[ "${sel}" -ge "${idx}" ]]; then
      if [[ "${NG_LANG}" == "en" ]]; then printf 'Invalid selection.\n'; else printf '无效选择。\n'; fi
      continue
    fi

    local node_name="${node_names[$((sel-1))]}"
    local node_host="${node_hosts[$((sel-1))]}"
    local node_port="${node_ports[$((sel-1))]}"
    local node_user="${node_users[$((sel-1))]}"
    local node_auth="${node_auths[$((sel-1))]}"
    local node_key="${node_keys[$((sel-1))]}"

    local -a ssh_opts=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p "${node_port}")
    local -a ssh_opts_interactive=(-t -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p "${node_port}")
    local use_sshpass=0

    if [[ "${node_auth}" == "password" ]] && command -v sshpass >/dev/null 2>&1; then
      use_sshpass=1
      export SSHPASS="${node_key}"
    else
      ssh_opts+=(-i "${node_key}")
      ssh_opts_interactive+=(-i "${node_key}")
    fi

    while true; do
      if [[ "${NG_LANG}" == "en" ]]; then
        printf '\nRemote execute on %s (%s):\n\n' "${node_name}" "${node_host}"
        printf '  [1] Run ServerHarbor online\n'
        printf '  [2] Install ServerHarbor\n'
        printf '  [3] Run installed ServerHarbor\n'
        printf '  [4] Custom command\n'
        printf '  [0] Back to node selection\n'
      else
        printf '\n在 %s (%s) 上远程执行：\n\n' "${node_name}" "${node_host}"
        printf '  [1] 运行在线版 ServerHarbor\n'
        printf '  [2] 安装 ServerHarbor\n'
        printf '  [3] 运行安装版 ServerHarbor\n'
        printf '  [4] 自定义命令\n'
        printf '  [0] 返回选择节点\n'
      fi

      printf '\n'
      ng_t select
      local op_choice
      ng_read_line op_choice || return 130

      [[ "${op_choice}" == "0" ]] && break

      local cmd=""

      case "${op_choice}" in
        1)
          cmd="bash <(curl -q -fsSL 'https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/run.sh?$(date +%s)')"
          ;;
        2)
          cmd="curl -q -fsSL 'https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/install.sh?$(date +%s)' | sudo bash"
          ;;
        3)
          cmd="shr"
          ;;
        4)
          if [[ "${NG_LANG}" == "en" ]]; then printf 'Enter command: '; else printf '输入命令：'; fi
          ng_read_line cmd || return 130
          ;;
        *)
          ng_t invalid_option
          continue
          ;;
      esac

      [[ -z "${cmd}" ]] && continue

      if [[ "${NG_LANG}" == "en" ]]; then
        printf '\nExecuting on %s ...\n\n' "${node_name}"
      else
        printf '\n正在 %s 上执行 ...\n\n' "${node_name}"
      fi

      local -a exec_ssh=()
      if [[ "${op_choice}" =~ ^[1-3]$ ]]; then
        if [[ "${use_sshpass}" -eq 1 ]]; then
          exec_ssh=(sshpass -e ssh "${ssh_opts_interactive[@]}" "${node_user}@${node_host}")
        else
          exec_ssh=(ssh "${ssh_opts_interactive[@]}" "${node_user}@${node_host}")
        fi
      else
        if [[ "${use_sshpass}" -eq 1 ]]; then
          exec_ssh=(sshpass -e ssh "${ssh_opts[@]}" "${node_user}@${node_host}")
        else
          exec_ssh=(ssh "${ssh_opts[@]}" "${node_user}@${node_host}")
        fi
      fi

      "${exec_ssh[@]}" "bash -c '${cmd}'"
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

      ng_press_enter || return 130
    done
  done
}

ng_node_menu() {
  local choice

  while true; do
    clear || true
    if [[ "${NG_LANG}" == "en" ]]; then
      ng_print_title_box "🛰 Node Management" "Multi-server management with SSH"
      ng_print_option "1" "📋" "Node list" "List / add / edit / remove nodes"
      ng_print_option "2" "🤝" "Setup mutual" "Bidirectional node registration"
      ng_print_option "3" "🚀" "Remote execute" "Run commands or presets on a node"
      ng_print_option "0" "↩" "Back"
    else
      ng_print_title_box "🛰 节点管理" "基于 SSH 的多服务器管理"
      ng_print_option "1" "📋" "节点列表" "列出 / 添加 / 修改 / 删除节点"
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
  done
}
