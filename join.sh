#!/usr/bin/env bash

set -euo pipefail

# ServerHarbor Join Command Generator
# Runs on the MAIN server to generate a registration command for a new node.
# Usage: bash join.sh [lang]

LANG_CHOICE="${1:-zh}"

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf '=== ServerHarbor Node Registration ===\n\n'
  printf 'This script registers a new node from the main server.\n'
  printf 'You need SSH access FROM this server TO the new server.\n\n'
  printf 'Enter new server IP: '
else
  printf '=== ServerHarbor 节点注册 ===\n\n'
  printf '此脚本在主服务器上运行，注册新节点。\n'
  printf '需要从本服务器 SSH 到新服务器。\n\n'
  printf '输入新服务器 IP：'
fi

read -r NEW_IP < /dev/tty
if [[ -z "${NEW_IP}" ]]; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then
    printf 'ERROR: IP is required.\n'
  else
    printf 'ERROR: IP 不能为空。\n'
  fi
  exit 1
fi

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf 'Enter node alias (e.g. hk-01): '
else
  printf '输入节点别名（如 hk-01）：'
fi

read -r ALIAS < /dev/tty
ALIAS="${ALIAS:-$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new root@"${NEW_IP}" hostname 2>/dev/null || echo "node-${NEW_IP##*.}")}"

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf 'Enter SSH port (default 22): '
else
  printf '输入 SSH 端口（默认 22）：'
fi

read -r SSH_PORT < /dev/tty
SSH_PORT="${SSH_PORT:-22}"

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf 'Enter SSH user (default root): '
else
  printf '输入 SSH 用户（默认 root）：'
fi

read -r SSH_USER < /dev/tty
SSH_USER="${SSH_USER:-root}"

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf '\nTesting SSH connection to %s@%s:%s ...\n' "${SSH_USER}" "${NEW_IP}" "${SSH_PORT}"
else
  printf '\n正在测试 SSH 连接 %s@%s:%s ...\n' "${SSH_USER}" "${NEW_IP}" "${SSH_PORT}"
fi

if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "${SSH_PORT}" "${SSH_USER}@${NEW_IP}" "echo OK" >/dev/null 2>&1; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then
    printf '✓ SSH connection successful.\n\n'
  else
    printf '✓ SSH 连接成功。\n\n'
  fi
else
  if [[ "${LANG_CHOICE}" == "en" ]]; then
    printf '✗ SSH connection failed. Please check credentials and try again.\n'
  else
    printf '✗ SSH 连接失败，请检查凭据后重试。\n'
  fi
  exit 1
fi

NODES_FILE="${HOME}/.config/serverharbor/servers.json"
if [[ -f "/opt/serverharbor/.serverharbor-install" ]]; then
  NODES_FILE="/opt/serverharbor/data/servers.json"
fi

mkdir -p "$(dirname "${NODES_FILE}")"
if [[ ! -f "${NODES_FILE}" ]]; then
  cat > "${NODES_FILE}" <<'EOF'
{"defaults":{"ssh":{"user":"root","port":22,"key":"~/.ssh/id_ed25519"}},"servers":[]}
EOF
fi

if jq -e --arg n "${ALIAS}" '.servers[] | select(.name == $n)' "${NODES_FILE}" >/dev/null 2>&1; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then
    printf 'Node "%s" already exists.\n' "${ALIAS}"
  else
    printf '节点 "%s" 已存在。\n' "${ALIAS}"
  fi
  exit 0
fi

TMP="${NODES_FILE}.tmp"
jq --arg name "${ALIAS}" \
   --arg host "${NEW_IP}" \
   --arg user "${SSH_USER}" \
   --arg port "${SSH_PORT}" \
   '.servers += [{name:$name,host:$host,ssh:{user:$user,port:($port|number),auth:"key",key:"~/.ssh/id_ed25519"},tags:[],enabled:true}]' \
   "${NODES_FILE}" > "${TMP}" && mv -f "${TMP}" "${NODES_FILE}"

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf '✓ Node "%s" (%s@%s:%s) registered successfully!\n' "${ALIAS}" "${SSH_USER}" "${NEW_IP}" "${SSH_PORT}"
else
  printf '✓ 节点 "%s" (%s@%s:%s) 注册成功！\n' "${ALIAS}" "${SSH_USER}" "${NEW_IP}" "${SSH_PORT}"
fi
