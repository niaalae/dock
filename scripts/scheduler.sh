#!/bin/bash
UTIL_DIR="/opt/utilities"
BIN="${UTIL_DIR}/syshealth"
CONFIG="${UTIL_DIR}/config/preferences.json"
PID_FILE="/var/run/syshealth.pid"

MIN_RUN_TIME=10800
MAX_RUN_TIME=18000
PAUSE_TIME=900

start_service() {
    "${BIN}" --config="${CONFIG}" --no-color &
    echo $! > "${PID_FILE}"
}

stop_service() {
    if [ -f "${PID_FILE}" ]; then
        kill $(cat "${PID_FILE}") 2>/dev/null
        rm -f "${PID_FILE}"
    fi
}

check_network() {
    # Check if VPN tunnel exists (if VPN was configured)
    if [ -f /etc/openvpn/auth.txt ]; then
        if ! ip addr show tun0 > /dev/null 2>&1; then
            stop_service
            bash "${UTIL_DIR}/scripts/network.sh" || true
        fi
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
    ELAPSED=0
    while [ $ELAPSED -lt $RUNTIME ]; do
        sleep 300
        ELAPSED=$((ELAPSED + 300))
        check_network
    done
    stop_service
    sleep ${PAUSE_TIME}
done
