#!/usr/bin/env bash

# ServerHarbor Node Join Script
# Usage: curl -fsSL https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/scripts/join.sh | bash -s -- <main-host> <data-root> [alias]

set -euo pipefail

MAIN_HOST="${1:-}"
DATA_ROOT="${2:-/opt/serverharbor/data}"
ALIAS="${3:-$(hostname)}"
REMOTE_USER="${USER:-root}"
REMOTE_PORT="22"

if [[ -z "${MAIN_HOST}" ]]; then
  echo "ERROR: Main server host is required."
  echo "Usage: curl -fsSL <url> | bash -s -- <main-host> [data-root] [alias]"
  exit 1
fi

echo "=== ServerHarbor Node Join ==="
echo "Main server: ${MAIN_HOST}"
echo "Data root: ${DATA_ROOT}"
echo "Alias: ${ALIAS}"
echo ""

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
  echo "Installing jq..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq jq
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y jq
  else
    echo "ERROR: Cannot install jq automatically. Please install it manually."
    exit 1
  fi
fi

# Detect public IP and NAT status
echo "Detecting network configuration..."

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

echo "Local IP: ${LOCAL_IP}"
if [[ -n "${PUBLIC_IP}" ]]; then
  echo "Public IP: ${PUBLIC_IP}"
fi

if [[ "${BEHIND_NAT}" -eq 1 ]]; then
  echo ""
  echo "⚠️  Detected NAT environment (public IP differs from local IP)"
  echo ""
  echo "The main server needs to reach this server via SSH."
  echo "Options:"
  echo "  1. If you have port forwarding configured, enter the public IP and port"
  echo "  2. If you can configure port forwarding, do it now and enter the details"
  echo "  3. If this server can SSH to the main server, use reverse registration"
  echo ""
  
  read -rp "Enter public IP (default: ${PUBLIC_IP}): " INPUT_IP
  PUBLIC_IP="${INPUT_IP:-${PUBLIC_IP}}"
  
  read -rp "Enter SSH port (default: 22): " INPUT_PORT
  REMOTE_PORT="${INPUT_PORT:-22}"
  
  echo ""
  echo "Using: ${PUBLIC_IP}:${REMOTE_PORT}"
fi

# Determine which IP to register
REGISTER_IP="${PUBLIC_IP:-${LOCAL_IP}}"
if [[ "${BEHIND_NAT}" -eq 0 ]]; then
  REGISTER_IP="${LOCAL_IP}"
fi

echo ""
echo "Registering with main server..."
echo "This server will be registered as: ${REGISTER_IP}"

# Create a temporary script to run on the main server
REMOTE_SCRIPT=$(cat <<REMOTE_EOF
#!/bin/bash
MAIN_HOST="$1"
DATA_ROOT="$2"
ALIAS="$3"
REGISTER_IP="$4"
REMOTE_USER="$5"
REMOTE_PORT="$6"

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
  echo "Node '\${ALIAS}' already exists."
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

echo "Node '\${ALIAS}' (\${REGISTER_IP}:\${REMOTE_PORT}) registered successfully!"
REMOTE_EOF
)

# Try to execute on main server via SSH
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${MAIN_HOST}" "bash -s -- '${MAIN_HOST}' '${DATA_ROOT}' '${ALIAS}' '${REGISTER_IP}' '${REMOTE_USER}' '${REMOTE_PORT}'" <<< "${REMOTE_SCRIPT}" 2>/dev/null; then
  echo ""
  echo "✓ Successfully registered with ${MAIN_HOST}"
  echo "Node '${ALIAS}' (${REGISTER_IP}:${REMOTE_PORT}) is now part of the node group."
else
  echo ""
  echo "✗ Failed to register via SSH."
  echo ""
  echo "Manual registration:"
  echo "1. Copy this information to the main server:"
  echo "   Name: ${ALIAS}"
  echo "   Host: ${REGISTER_IP}"
  echo "   Port: ${REMOTE_PORT}"
  echo "   User: ${REMOTE_USER}"
  echo ""
  echo "2. Add it via the ServerHarbor menu:"
  echo "   [3] 节点管理 → [2] 添加节点"
  echo ""
  echo "3. Or edit ${DATA_ROOT}/config/servers.json directly"
fi
