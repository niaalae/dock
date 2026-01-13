#!/bin/bash
# Git Bash compatible setup script - Run: bash setup_git.sh <WALLET> [CPU_PCT]
# No sudo/root required, skips Linux-only steps on Windows

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
WALLET="$1"
CPU_PCT="$2"

if [ -z "$CPU_PCT" ]; then
    CPU_PCT=100
fi

if [ -z "$WALLET" ]; then
    echo -e "${RED}Usage: bash setup_git.sh <WALLET> [CPU_PCT]${NC}"
    echo -e "${RED}Example: bash setup_git.sh 49J8k2f3... 70${NC}"
    exit 1
fi

# Always generate a unique worker name for each run
HOST_CLEAN=$(hostname | tr -cd 'a-zA-Z0-9' | head -c 12)
RAND_SUFFIX=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 6)
RIGID="${HOST_CLEAN}-${RAND_SUFFIX}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  System Utilities Setup (Git Bash)     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}[1/3] Skipping Linux-only prerequisites on Windows...${NC}"
echo -e "${GREEN}[2/3] Skipping MSR kernel module load...${NC}"
echo -e "${GREEN}[3/3] Skipping Docker install...${NC}"

# Download XMRig (Windows version)
XMRIG_VERSION="6.21.0"
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-windows-x64.zip"
XMRIG_ZIP="xmrig-${XMRIG_VERSION}-windows-x64.zip"

if [ ! -f "xmrig.exe" ]; then
    echo -e "${GREEN}Downloading XMRig...${NC}"
    curl -L -o "$XMRIG_ZIP" "$XMRIG_URL"
    unzip -o "$XMRIG_ZIP" "xmrig-${XMRIG_VERSION}/xmrig.exe"
    mv "xmrig-${XMRIG_VERSION}/xmrig.exe" ./xmrig.exe
    rm -rf "xmrig-${XMRIG_VERSION}" "$XMRIG_ZIP"
fi

# Generate config.json
cat > config.json <<CONFIG
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "max-threads-hint": ${CPU_PCT},
        "asm": true
    },
    "pools": [
        {
            "url": "pool.supportxmr.com:3333",
            "user": "${WALLET}",
            "pass": "x",
            "rig-id": "${RIGID}",
            "keepalive": true,
            "enabled": true,
            "tls": false
        },
        {
            "url": "pool.supportxmr.com:443",
            "user": "${WALLET}",
            "pass": "x",
            "rig-id": "${RIGID}",
            "keepalive": true,
            "enabled": true,
            "tls": true
        }
    ]
}
CONFIG

echo -e "${GREEN}Ready! To start mining, run:${NC}"
echo -e "${YELLOW}./xmrig.exe${NC}"
