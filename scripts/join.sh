#!/usr/bin/env bash

# ServerHarbor Node Join Script
# Usage: curl -fsSL https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/scripts/join.sh | bash -s -- <main-host> <data-root> [alias] [lang]

set -euo pipefail

MAIN_HOST="${1:-}"
DATA_ROOT="${2:-/opt/serverharbor/data}"
ALIAS="${3:-$(hostname)}"
LANG_CHOICE="${4:-zh}"
REMOTE_USER="${USER:-root}"
REMOTE_PORT="22"

# Language strings
if [[ "${LANG_CHOICE}" == "en" ]]; then
  MSG_TITLE="ServerHarbor Node Join"
  MSG_MAIN_SERVER="Main server"
  MSG_DATA_ROOT="Data root"
  MSG_ALIAS="Alias"
  MSG_INSTALLING_JQ="Installing jq..."
  MSG_DETECTING="Detecting network configuration..."
  MSG_LOCAL_IP="Local IP"
  MSG_PUBLIC_IP="Public IP"
  MSG_NAT_DETECTED="Detected NAT environment (public IP differs from local IP)"
  MSG_NAT_OPTIONS="The main server needs to reach this server via SSH."
  MSG_NAT_OPT1="If you have port forwarding configured, enter the public IP and port"
  MSG_NAT_OPT2="If you can configure port forwarding, do it now and enter the details"
  MSG_NAT_OPT3="If this server can SSH to the main server, use reverse registration"
  MSG_ENTER_IP="Enter public IP (default: %s): "
  MSG_ENTER_PORT="Enter SSH port (default: 22): "
  MSG_USING="Using"
  MSG_REGISTERING="Registering with main server..."
  MSG_REGISTER_AS="This server will be registered as"
  MSG_SUCCESS="✓ Successfully registered with %s"
  MSG_SUCCESS_DETAIL="Node '%s' (%s:%s) is now part of the node group."
  MSG_FAILED="✗ Failed to register via SSH."
  MSG_MANUAL="Manual registration"
  MSG_COPY_INFO="Copy this information to the main server"
  MSG_NAME="Name"
  MSG_HOST="Host"
  MSG_PORT="Port"
  MSG_USER="User"
  MSG_ADD_VIA_MENU="Add it via the ServerHarbor menu"
  MSG_MENU_PATH="[3] Node Management → [2] Add node"
  MSG_OR_EDIT="Or edit %s directly"
  MSG_ERROR_HOST="Main server host is required."
  MSG_ERROR_USAGE="Usage: curl -fsSL <url> | bash -s -- <main-host> [data-root] [alias] [lang]"
  MSG_ERROR_JQ="Cannot install jq automatically. Please install it manually."
  MSG_NODE_EXISTS="Node '%s' already exists."
  MSG_NODE_REGISTERED="Node '%s' (%s:%s) registered successfully!"
else
  MSG_TITLE="ServerHarbor 节点加入"
  MSG_MAIN_SERVER="主服务器"
  MSG_DATA_ROOT="数据目录"
  MSG_ALIAS="别名"
  MSG_INSTALLING_JQ="正在安装 jq..."
  MSG_DETECTING="正在检测网络配置..."
  MSG_LOCAL_IP="本地 IP"
  MSG_PUBLIC_IP="公网 IP"
  MSG_NAT_DETECTED="检测到 NAT 环境（公网 IP 与本地 IP 不同）"
  MSG_NAT_OPTIONS="主服务器需要通过 SSH 访问此服务器。"
  MSG_NAT_OPT1="如果已配置端口转发，请输入公网 IP 和端口"
  MSG_NAT_OPT2="如果可以配置端口转发，请现在配置并输入详情"
  MSG_NAT_OPT3="如果此服务器可以 SSH 到主服务器，使用反向注册"
  MSG_ENTER_IP="输入公网 IP（默认: %s）: "
  MSG_ENTER_PORT="输入 SSH 端口（默认: 22）: "
  MSG_USING="使用"
  MSG_REGISTERING="正在注册到主服务器..."
  MSG_REGISTER_AS="此服务器将被注册为"
  MSG_SUCCESS="✓ 成功注册到 %s"
  MSG_SUCCESS_DETAIL="节点 '%s' (%s:%s) 已加入节点组。"
  MSG_FAILED="✗ 通过 SSH 注册失败。"
  MSG_MANUAL="手动注册"
  MSG_COPY_INFO="将此信息复制到主服务器"
  MSG_NAME="名称"
  MSG_HOST="主机"
  MSG_PORT="端口"
  MSG_USER="用户"
  MSG_ADD_VIA_MENU="通过 ServerHarbor 菜单添加"
  MSG_MENU_PATH="[3] 节点管理 → [2] 添加节点"
  MSG_OR_EDIT="或直接编辑 %s"
  MSG_ERROR_HOST="需要主服务器地址。"
  MSG_ERROR_USAGE="用法: curl -fsSL <url> | bash -s -- <主服务器> [数据目录] [别名] [语言]"
  MSG_ERROR_JQ="无法自动安装 jq，请手动安装。"
  MSG_NODE_EXISTS="节点 '%s' 已存在。"
  MSG_NODE_REGISTERED="节点 '%s' (%s:%s) 注册成功！"
fi

if [[ -z "${MAIN_HOST}" ]]; then
  echo "ERROR: ${MSG_ERROR_HOST}"
  echo "${MSG_ERROR_USAGE}"
  exit 1
fi

echo "=== ${MSG_TITLE} ==="
echo "${MSG_MAIN_SERVER}: ${MAIN_HOST}"
echo "${MSG_DATA_ROOT}: ${DATA_ROOT}"
echo "${MSG_ALIAS}: ${ALIAS}"
echo ""

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
  echo "${MSG_INSTALLING_JQ}"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq jq
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y jq
  else
    echo "ERROR: ${MSG_ERROR_JQ}"
    exit 1
  fi
fi

# Detect public IP and NAT status
echo "${MSG_DETECTING}"

# Get local IPs
LOCAL_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' || echo "unknown")
LOCAL_IP=$(echo "${LOCAL_IPS}" | head -1)

# Try to get public IP
PUBLIC_IP=""
if command -v curl >/dev/null 2>&1; then
  PUBLIC_IP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "")
fi

# Check if behind NAT
BEHIND_NAT=0
if [[ -n "${PUBLIC_IP}" ]] && [[ "${PUBLIC_IP}" != "${LOCAL_IP}" ]]; then
  BEHIND_NAT=1
fi

echo "${MSG_LOCAL_IP}: ${LOCAL_IP}"
if [[ -n "${PUBLIC_IP}" ]]; then
  echo "${MSG_PUBLIC_IP}: ${PUBLIC_IP}"
fi

if [[ "${BEHIND_NAT}" -eq 1 ]]; then
  echo ""
  echo "⚠️  ${MSG_NAT_DETECTED}"
  echo ""
  echo "${MSG_NAT_OPTIONS}"
  echo "  1. ${MSG_NAT_OPT1}"
  echo "  2. ${MSG_NAT_OPT2}"
  echo "  3. ${MSG_NAT_OPT3}"
  echo ""
  
  read -rp "$(printf "${MSG_ENTER_IP}" "${PUBLIC_IP}")" INPUT_IP
  PUBLIC_IP="${INPUT_IP:-${PUBLIC_IP}}"
  
  read -rp "${MSG_ENTER_PORT}" INPUT_PORT
  REMOTE_PORT="${INPUT_PORT:-22}"
  
  echo ""
  echo "${MSG_USING}: ${PUBLIC_IP}:${REMOTE_PORT}"
fi

# Determine which IP to register
REGISTER_IP="${PUBLIC_IP:-${LOCAL_IP}}"
if [[ "${BEHIND_NAT}" -eq 0 ]]; then
  REGISTER_IP="${LOCAL_IP}"
fi

echo ""
echo "${MSG_REGISTERING}"
echo "${MSG_REGISTER_AS}: ${REGISTER_IP}"

# Create a temporary script to run on the main server
REMOTE_SCRIPT=$(cat <<REMOTE_EOF
#!/bin/bash
MAIN_HOST="\$1"
DATA_ROOT="\$2"
ALIAS="\$3"
REGISTER_IP="\$4"
REMOTE_USER="\$5"
REMOTE_PORT="\$6"

NODES_FILE="\${DATA_ROOT}/config/servers.json"

# Initialize if needed
if [[ ! -f "\${NODES_FILE}" ]]; then
  mkdir -p "\$(dirname "\${NODES_FILE}")"
  cat > "\${NODES_FILE}" <<EOF
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

# Check if node already exists
if jq -e ".servers[] | select(.name == \\\"\${ALIAS}\\\")" "\${NODES_FILE}" >/dev/null 2>&1; then
  echo "EXISTS:\${ALIAS}"
  exit 0
fi

# Add node
TMP_FILE="\${NODES_FILE}.tmp"
jq --arg name "\${ALIAS}" \\
   --arg host "\${REGISTER_IP}" \\
   --arg user "\${REMOTE_USER}" \\
   --arg port "\${REMOTE_PORT}" \\
   '.servers += [{
     "name": \$name,
     "host": \$host,
     "ssh": {
       "user": \$user,
       "port": (\$port | tonumber),
       "auth": "key",
       "key": "~/.ssh/id_ed25519"
     },
     "tags": [],
     "enabled": true
   }]' "\${NODES_FILE}" > "\${TMP_FILE}" && mv -f "\${TMP_FILE}" "\${NODES_FILE}"

echo "OK:\${ALIAS}:\${REGISTER_IP}:\${REMOTE_PORT}"
REMOTE_EOF
)

# Try to execute on main server via SSH
REMOTE_OUTPUT=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${MAIN_HOST}" "bash -s -- '${MAIN_HOST}' '${DATA_ROOT}' '${ALIAS}' '${REGISTER_IP}' '${REMOTE_USER}' '${REMOTE_PORT}'" <<< "${REMOTE_SCRIPT}" 2>/dev/null) || true

if echo "${REMOTE_OUTPUT}" | grep -q "^OK:"; then
  echo ""
  printf "${MSG_SUCCESS}\n" "${MAIN_HOST}"
  printf "${MSG_SUCCESS_DETAIL}\n" "${ALIAS}" "${REGISTER_IP}" "${REMOTE_PORT}"
elif echo "${REMOTE_OUTPUT}" | grep -q "^EXISTS:"; then
  echo ""
  printf "${MSG_NODE_EXISTS}\n" "${ALIAS}"
else
  echo ""
  echo "${MSG_FAILED}"
  echo ""
  echo "${MSG_MANUAL}:"
  echo "1. ${MSG_COPY_INFO}:"
  echo "   ${MSG_NAME}: ${ALIAS}"
  echo "   ${MSG_HOST}: ${REGISTER_IP}"
  echo "   ${MSG_PORT}: ${REMOTE_PORT}"
  echo "   ${MSG_USER}: ${REMOTE_USER}"
  echo ""
  echo "2. ${MSG_ADD_VIA_MENU}:"
  echo "   ${MSG_MENU_PATH}"
  echo ""
  printf "3. ${MSG_OR_EDIT}\n" "${DATA_ROOT}/config/servers.json"
fi
