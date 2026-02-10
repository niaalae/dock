#!/bin/bash

# Worker Manager - Spawns and manages multiple autoS.sh instances
# Usage: ./worker-manager.sh <number_of_instances> <tokens_file>

INSTANCES="$1"
TOKENS_FILE="${2:-tokens.txt}"  # File with one GitHub token per line
SCRIPT="./autoS-optimized.sh"

if [ -z "$INSTANCES" ]; then
  echo "Usage: $0 <number_of_instances> [tokens_file]"
  exit 1
fi

if [ ! -f "$TOKENS_FILE" ]; then
  echo "Tokens file not found: $TOKENS_FILE"
  exit 1
fi

# System optimization
echo "Optimizing system for $INSTANCES instances..."

# Increase file descriptor limits
ulimit -n 100000

# Increase max processes
ulimit -u 100000

# Kernel tuning (requires root)
if [ "$EUID" -eq 0 ]; then
  # Increase max connections
  sysctl -w net.core.somaxconn=65535
  sysctl -w net.ipv4.ip_local_port_range="1024 65535"
  sysctl -w net.ipv4.tcp_tw_reuse=1
  sysctl -w net.ipv4.tcp_fin_timeout=30
  
  # Increase file handles
  sysctl -w fs.file-max=2097152
  
  # Reduce swap usage
  sysctl -w vm.swappiness=10
  
  echo "Kernel parameters optimized."
else
  echo "Warning: Not running as root. Some optimizations skipped."
fi

# Read tokens into array
mapfile -t TOKENS < "$TOKENS_FILE"
TOKEN_COUNT=${#TOKENS[@]}

if [ $TOKEN_COUNT -eq 0 ]; then
  echo "No tokens found in $TOKENS_FILE"
  exit 1
fi

echo "Loaded $TOKEN_COUNT tokens"
echo "Starting $INSTANCES instances..."

# Spawn instances
for i in $(seq 1 $INSTANCES); do
  # Round-robin token selection
  TOKEN_INDEX=$((i % TOKEN_COUNT))
  TOKEN="${TOKENS[$TOKEN_INDEX]}"
  
  # Start instance in background with nice priority
  nice -n 19 "$SCRIPT" "$TOKEN" "$i" &
  
  # Stagger startup to avoid overwhelming the system
  if [ $((i % 50)) -eq 0 ]; then
    echo "Started $i instances..."
    sleep 2
  fi
done

echo "All $INSTANCES instances started!"
echo "Logs are in /tmp/autoS-*.log"
echo "Monitor with: tail -f /tmp/autoS-*.log"

# Keep script running and monitor
while true; do
  RUNNING=$(pgrep -f "autoS-optimized.sh" | wc -l)
  echo "[$(date)] Running instances: $RUNNING / $INSTANCES"
  sleep 300  # Report every 5 minutes
done
