#!/usr/bin/env bash

set -euo pipefail

# ServerHarbor Join Script
# Runs on the MAIN server to register a new node via SSH.
# Usage: bash join.sh [lang]

LANG_CHOICE="${1:-zh}"

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf '=== ServerHarbor Node Registration ===\n\n'
  printf 'Register a new node from this server.\n'
  printf 'Requires SSH access FROM this server TO the new server.\n\n'
  printf 'Enter new server IP: '
else
  printf '=== ServerHarbor 节点注册 ===\n\n'
  printf '在主服务器上注册新节点。\n'
  printf '需要从本服务器 SSH 到新服务器。\n\n'
  printf '输入新服务器 IP：'
fi

read -r NEW_IP < /dev/tty
if [[ -z "${NEW_IP}" ]]; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then printf 'ERROR: IP required.\n'; else printf 'ERROR: IP 不能为空。\n'; fi
  exit 1
fi

if [[ "${LANG_CHOICE}" == "en" ]]; then printf 'Enter node alias: '; else printf '输入节点别名：'; fi
read -r ALIAS < /dev/tty
ALIAS="${ALIAS:-node-${NEW_IP##*.}}"

if [[ "${LANG_CHOICE}" == "en" ]]; then printf 'SSH port (default 22): '; else printf 'SSH 端口（默认 22）：'; fi
read -r SSH_PORT < /dev/tty
SSH_PORT="${SSH_PORT:-22}"

if [[ "${LANG_CHOICE}" == "en" ]]; then printf 'SSH user (default root): '; else printf 'SSH 用户（默认 root）：'; fi
read -r SSH_USER < /dev/tty
SSH_USER="${SSH_USER:-root}"

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf 'Auth method: [1] SSH key [2] Password: '
else
  printf '认证方式：[1] SSH 密钥 [2] 密码：'
fi
read -r AUTH_CHOICE < /dev/tty
AUTH_CHOICE="${AUTH_CHOICE:-1}"

SSH_AUTH="key"
SSH_PASS=""

if [[ "${AUTH_CHOICE}" == "2" ]]; then
  SSH_AUTH="password"
  if [[ "${LANG_CHOICE}" == "en" ]]; then printf 'Enter password: '; else printf '输入密码：'; fi
  read -rs SSH_PASS < /dev/tty
  printf '\n'

  if ! command -v sshpass >/dev/null 2>&1; then
    if [[ "${EUID}" -ne 0 ]]; then
      if [[ "${LANG_CHOICE}" == "en" ]]; then printf 'ERROR: sshpass required. Install or use key auth.\n'; else printf 'ERROR: 需要 sshpass，请安装或使用密钥。\n'; fi
      exit 1
    fi
    if [[ "${LANG_CHOICE}" == "en" ]]; then printf 'Installing sshpass...\n'; else printf '正在安装 sshpass...\n'; fi
    if command -v apt-get >/dev/null 2>&1; then apt-get install -y -qq sshpass 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then yum install -y sshpass 2>/dev/null || true
    elif command -v dnf >/dev/null 2>&1; then dnf install -y sshpass 2>/dev/null || true
    fi
  fi
fi

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf '\nTesting SSH %s@%s:%s ...\n' "${SSH_USER}" "${NEW_IP}" "${SSH_PORT}"
else
  printf '\n测试 SSH %s@%s:%s ...\n' "${SSH_USER}" "${NEW_IP}" "${SSH_PORT}"
fi

SSH_TEST_OK=0
if [[ "${SSH_AUTH}" == "password" ]] && command -v sshpass >/dev/null 2>&1; then
  if sshpass -p "${SSH_PASS}" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "${SSH_PORT}" "${SSH_USER}@${NEW_IP}" "echo OK" >/dev/null 2>&1; then
    SSH_TEST_OK=1
  fi
else
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "${SSH_PORT}" "${SSH_USER}@${NEW_IP}" "echo OK" >/dev/null 2>&1; then
    SSH_TEST_OK=1
  fi
fi

if [[ "${SSH_TEST_OK}" -ne 1 ]]; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then printf '✗ SSH failed. Check credentials.\n'; else printf '✗ SSH 连接失败，请检查凭据。\n'; fi
  exit 1
fi

if [[ "${LANG_CHOICE}" == "en" ]]; then printf '✓ SSH connected.\n\n'; else printf '✓ SSH 连接成功。\n\n'; fi

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

if ! command -v jq >/dev/null 2>&1; then
  if [[ "${EUID}" -eq 0 ]]; then
    if command -v apt-get >/dev/null 2>&1; then apt-get install -y -qq jq 2>/dev/null
    elif command -v yum >/dev/null 2>&1; then yum install -y jq 2>/dev/null
    elif command -v dnf >/dev/null 2>&1; then dnf install -y jq 2>/dev/null
    fi
  else
    if [[ "${LANG_CHOICE}" == "en" ]]; then printf 'ERROR: jq required.\n'; else printf 'ERROR: 需要 jq。\n'; fi
    exit 1
  fi
fi

if jq -e --arg n "${ALIAS}" '.servers[] | select(.name == $n)' "${NODES_FILE}" >/dev/null 2>&1; then
  if [[ "${LANG_CHOICE}" == "en" ]]; then printf 'Node "%s" already exists.\n' "${ALIAS}"; else printf '节点 "%s" 已存在。\n' "${ALIAS}"; fi
  exit 0
fi

TMP="${NODES_FILE}.tmp"
jq --arg name "${ALIAS}" \
   --arg host "${NEW_IP}" \
   --arg user "${SSH_USER}" \
   --arg port "${SSH_PORT}" \
   --arg auth "${SSH_AUTH}" \
   --arg key "$( [[ "${SSH_AUTH}" == "key" ]] && echo "~/.ssh/id_ed25519" || echo "" )" \
   '.servers += [{name:$name,host:$host,ssh:{user:$user,port:($port|number),auth:$auth,key:$key},tags:[],enabled:true}]' \
   "${NODES_FILE}" > "${TMP}" && mv -f "${TMP}" "${NODES_FILE}"

if [[ "${LANG_CHOICE}" == "en" ]]; then
  printf '✓ Node "%s" (%s@%s:%s) registered!\n' "${ALIAS}" "${SSH_USER}" "${NEW_IP}" "${SSH_PORT}"
else
  printf '✓ 节点 "%s" (%s@%s:%s) 注册成功！\n' "${ALIAS}" "${SSH_USER}" "${NEW_IP}" "${SSH_PORT}"
fi
