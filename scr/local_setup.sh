#!/bin/bash
# local_setup.sh - Local (non-Docker) setup for syshealth (XMRig) miner
# Usage: ./local_setup.sh <WALLET> <CPU_PCT> <WORKER_NAME>

set -e

if [ $# -ne 3 ]; then
  echo "Usage: $0 <WALLET> <CPU_PCT> <WORKER_NAME>"
  exit 1
fi

WALLET="$1"
CPU_PCT="$2"
WORKER_NAME="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
PREFS_FILE="$CONFIG_DIR/preferences.json"

# Ensure dependencies
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed. Aborting."; exit 1; }

# Download syshealth (XMRig) if not present
if [ ! -f "$SCRIPT_DIR/syshealth" ]; then
  XMRIG_VERSION="6.21.0"
  echo "Downloading XMRig $XMRIG_VERSION..."
  curl -L -o /tmp/xmrig.tar.gz "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz"
  tar -xzf /tmp/xmrig.tar.gz -C /tmp
  mv "/tmp/xmrig-${XMRIG_VERSION}/xmrig" "$SCRIPT_DIR/syshealth"
  chmod +x "$SCRIPT_DIR/syshealth"
  rm -rf /tmp/xmrig* /tmp/xmrig-${XMRIG_VERSION}
fi

# Create config directory if needed
mkdir -p "$CONFIG_DIR"

# Generate preferences.json
cat > "$PREFS_FILE" <<EOF
{
  "wallet": "$WALLET",
  "cpu_pct": $CPU_PCT,
  "worker_name": "$WORKER_NAME",
  "log-file": "$SCRIPT_DIR/xmrig.log"
}
EOF

echo "local_setup.sh complete. Preferences written to $PREFS_FILE."
