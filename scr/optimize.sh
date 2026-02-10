#!/bin/bash
# optimize_mining_linux.sh - System tweaks for maximum mining performance
# Usage: sudo bash optimize_mining_linux.sh

set -e

# Detect if running in GitHub Actions or CI
if [ "$GITHUB_ACTIONS" = "true" ] || [ "$CI" = "true" ]; then
  echo "Running in CI/GitHub Actions: Skipping privileged hardware optimizations."
  echo "System mining optimizations not applied in CI environments."
  exit 0
fi

# 1. Enable huge pages (adjust value for your RAM, e.g. 128 for 2GB, 256 for 4GB, etc.)
HUGEPAGES=128
if [ -n "$1" ]; then
  HUGEPAGES="$1"
fi

echo "Setting vm.nr_hugepages=$HUGEPAGES"
sysctl -w vm.nr_hugepages=$HUGEPAGES

grep -q 'vm.nr_hugepages' /etc/sysctl.conf || echo "vm.nr_hugepages=$HUGEPAGES" >> /etc/sysctl.conf

# 2. Allow locking memory (for huge pages)
if ! grep -q 'ulimit -l unlimited' /etc/security/limits.conf; then
  echo '* soft memlock unlimited' >> /etc/security/limits.conf
  echo '* hard memlock unlimited' >> /etc/security/limits.conf
fi

# 3. Set CPU governor to performance (if available)
if command -v cpupower >/dev/null 2>&1; then
  cpupower frequency-set -g performance
elif command -v cpufreq-set >/dev/null 2>&1; then
  cpufreq-set -r -g performance
else
  echo "cpupower/cpufreq-set not found, skipping CPU governor tweak."
fi

# 4. Disable turbo boost (optional, for thermal stability)
if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
  echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
fi

# 5. Print summary
cat <<EOF

System mining optimizations applied:
- Huge pages: $HUGEPAGES
- Memory lock: unlimited
- CPU governor: performance (if supported)
- Turbo boost: disabled (if supported)

Reboot recommended for all changes to take effect.
EOF
