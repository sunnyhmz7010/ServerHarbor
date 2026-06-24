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

# Get local IP
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
echo "Local IP: ${LOCAL_IP}"

# Try to register via SSH
echo ""
echo "Registering with main server..."

# Create a temporary script to run on the main server
REMOTE_SCRIPT=$(cat <<'REMOTE_EOF'
#!/bin/bash
MAIN_HOST="$1"
DATA_ROOT="$2"
ALIAS="$3"
LOCAL_IP="$4"
REMOTE_USER="$5"

NODES_FILE="${DATA_ROOT}/config/servers.json"

# Initialize if needed
if [[ ! -f "${NODES_FILE}" ]]; then
  mkdir -p "$(dirname "${NODES_FILE}")"
  cat > "${NODES_FILE}" <<EOF
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
if jq -e ".servers[] | select(.name == \"${ALIAS}\")" "${NODES_FILE}" >/dev/null 2>&1; then
  echo "Node '${ALIAS}' already exists."
  exit 0
fi

# Add node
TMP_FILE="${NODES_FILE}.tmp"
jq --arg name "${ALIAS}" \
   --arg host "${LOCAL_IP}" \
   --arg user "${REMOTE_USER}" \
   '.servers += [{
     "name": $name,
     "host": $host,
     "ssh": {
       "user": $user,
       "port": 22,
       "auth": "key",
       "key": "~/.ssh/id_ed25519"
     },
     "tags": [],
     "enabled": true
   }]' "${NODES_FILE}" > "${TMP_FILE}" && mv -f "${TMP_FILE}" "${NODES_FILE}"

echo "Node '${ALIAS}' (${LOCAL_IP}) registered successfully!"
REMOTE_EOF
)

# Try to execute on main server via SSH
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${MAIN_HOST}" "bash -s -- '${MAIN_HOST}' '${DATA_ROOT}' '${ALIAS}' '${LOCAL_IP}' '${REMOTE_USER}'" <<< "${REMOTE_SCRIPT}" 2>/dev/null; then
  echo ""
  echo "✓ Successfully registered with ${MAIN_HOST}"
  echo "Node '${ALIAS}' is now part of the node group."
else
  echo ""
  echo "✗ Failed to register via SSH."
  echo ""
  echo "Manual registration:"
  echo "1. Copy this information to the main server:"
  echo "   Name: ${ALIAS}"
  echo "   Host: ${LOCAL_IP}"
  echo "   User: ${REMOTE_USER}"
  echo ""
  echo "2. Add it via the ServerHarbor menu:"
  echo "   [3] 节点管理 → [2] 添加节点"
  echo ""
  echo "3. Or edit ${DATA_ROOT}/config/servers.json directly"
fi
