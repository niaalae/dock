#!/bin/bash
set -e

UTIL_DIR="/opt/utilities"
SCRIPTS_DIR="${UTIL_DIR}/scripts"

cleanup() {
    pkill -f syshealth 2>/dev/null || true
    protonvpn disconnect 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

bash "${SCRIPTS_DIR}/setup.sh"
bash "${SCRIPTS_DIR}/network.sh"
bash "${SCRIPTS_DIR}/scheduler.sh"
