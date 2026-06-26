#!/usr/bin/env bash

set -euo pipefail

MAIN_SERVER="${1:-}"
ALIAS="${2:-$(hostname)}"
LANG_CHOICE="${3:-zh}"

if [[ -z "${MAIN_SERVER}" ]]; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then
    printf 'ERROR: Main server IP is required.\n'
    printf 'Usage: curl -fsSL <url> | bash -s -- <main-server-ip> [alias] [en]\n'
  else
    printf 'ERROR: 需要主服务器 IP。\n'
    printf '用法: curl -fsSL <url> | bash -s -- <主服务器IP> [别名] [zh]\n'
  fi
  exit 1
fi

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf '=== ServerHarbor Node Join ===\n'
  printf 'Main server: %s\n' "${MAIN_SERVER}"
  printf 'Alias:       %s\n\n' "${ALIAS}"
else
  printf '=== ServerHarbor 节点加入 ===\n'
  printf '主服务器: %s\n' "${MAIN_SERVER}"
  printf '别名:     %s\n\n' "${ALIAS}"
fi

if ! command -v jq >/dev/null 2>&1; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then
    printf 'Installing jq...\n'
  else
    printf '正在安装 jq...\n'
  fi
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq jq
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y jq
  else
    if [[ "${LANG_CHOICE}" == "en" ]]; then
      printf 'ERROR: Cannot install jq. Please install it manually.\n'
    else
      printf 'ERROR: 无法自动安装 jq，请手动安装。\n'
    fi
    exit 1
  fi
fi

MY_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf 'Local IP:    %s\n' "${MY_IP}"
  printf 'Registering with main server...\n\n'
else
  printf '本地 IP:     %s\n' "${MY_IP}"
  printf '正在注册到主服务器...\n\n'
fi

NODES_FILE="/opt/serverharbor/data/servers.json"

REMOTE_SCRIPT=$(cat <<'REMOTE_EOF'
#!/bin/bash
NODES="$1"
ALIAS="$2"
IP="$3"

if [[ ! -f "${NODES}" ]]; then
  mkdir -p "$(dirname "${NODES}")"
  cat > "${NODES}" <<'EOF'
{"defaults":{"ssh":{"user":"root","port":22,"key":"~/.ssh/id_ed25519"}},"servers":[]}
EOF
fi

if jq -e --arg n "${ALIAS}" '.servers[] | select(.name == $n)' "${NODES}" >/dev/null 2>&1; then
  echo "EXISTS:${ALIAS}"
  exit 0
fi

TMP="${NODES}.tmp"
jq --arg n "${ALIAS}" --arg h "${IP}" \
  '.servers += [{name:$n,host:$h,ssh:{user:"root",port:22,auth:"key",key:"~/.ssh/id_ed25519"},tags:[],enabled:true}]' \
  "${NODES}" > "${TMP}" && mv -f "${TMP}" "${NODES}"

echo "OK:${ALIAS}:${IP}"
REMOTE_EOF
)

OUTPUT=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new root@"${MAIN_SERVER}" \
  "bash -s -- '${NODES_FILE}' '${ALIAS}' '${MY_IP}'" <<< "${REMOTE_SCRIPT}" 2>&1) || true

if echo "${OUTPUT}" | grep -q "^OK:"; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then
    printf '✓ Successfully registered!\n'
    printf '  Node "%s" (%s) is now part of the node group.\n' "${ALIAS}" "${MY_IP}"
  else
    printf '✓ 注册成功！\n'
    printf '  节点 "%s" (%s) 已加入节点组。\n' "${ALIAS}" "${MY_IP}"
  fi
elif echo "${OUTPUT}" | grep -q "^EXISTS:"; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then
    printf 'Node "%s" already exists on the main server.\n' "${ALIAS}"
  else
    printf '节点 "%s" 已存在于主服务器上。\n' "${ALIAS}"
  fi
else
  if [[ "${LANG_CHOICE}" == "en" ]]; then
    printf '✗ Registration failed.\n\n'
    printf 'Manual registration:\n'
    printf '  1. SSH to the main server: ssh root@%s\n' "${MAIN_SERVER}"
    printf '  2. Add via menu: [3] Node Management → [2] Add node\n'
    printf '     Name: %s  Host: %s\n' "${ALIAS}" "${MY_IP}"
  else
    printf '✗ 注册失败。\n\n'
    printf '手动注册：\n'
    printf '  1. SSH 到主服务器：ssh root@%s\n' "${MAIN_SERVER}"
    printf '  2. 通过菜单添加：[3] 节点管理 → [2] 添加节点\n'
    printf '     名称: %s  主机: %s\n' "${ALIAS}" "${MY_IP}"
  fi
fi
