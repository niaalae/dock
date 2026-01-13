#!/usr/bin/env bash
set -euo pipefail

# Minimal non-sudo installer/runner for Tor (optional) and xmrig (prebuilt)
# Usage: scripts/run_miner.sh --pool POOL_URL --user USERNAME [--tor] [--threads-percent 50]

WORKDIR="$HOME/.local"
SRC="$WORKDIR/src"
BIN="$WORKDIR/bin"
mkdir -p "$SRC" "$BIN"

TOR_VERSION="0.4.6.10"
XM_VERSION="6.18.1"
USE_TOR=0
THREADS_PERCENT=50

# Generate a unique rig id (hostname + random suffix)
HOST_CLEAN=$(hostname 2>/dev/null | tr -cd 'a-zA-Z0-9' | head -c 12 || echo "host")
RAND_SUFFIX=$(head -c 100 /dev/urandom 2>/dev/null | tr -dc 'a-z0-9' | head -c 6 || echo "$RANDOM")
RIGID="${HOST_CLEAN}-${RAND_SUFFIX}"
print_usage(){
  cat <<EOF
Usage: $0 --pool POOL_URL --user USERNAME [--tor] [--threads-percent N]
  --pool            Mining pool URL (required)
  --user            Wallet or worker name (required)
  --tor             Build and start Tor locally (no sudo) and route xmrig through it
  --threads-percent CPU percent limit for xmrig (default: 50)
EOF
  exit 1
}

if [ "$#" -eq 0 ]; then
  print_usage
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pool) POOL_URL="$2"; shift 2;;
    --user) POOL_USER="$2"; shift 2;;
    --tor) USE_TOR=1; shift;;
    --threads-percent) THREADS_PERCENT="$2"; shift 2;;
    -h|--help) print_usage;;
    *) echo "Unknown arg: $1"; print_usage;;
  esac
done

if [ -z "${POOL_URL:-}" ] || [ -z "${POOL_USER:-}" ]; then
  echo "--pool and --user are required"
  print_usage
fi

# Build a proper wallet.worker `user` value so pools list a unique worker
# Extract base wallet (strip any existing ".worker" suffix) and append a
# sanitized rig id. Keep full RIGID for `rig-id` metadata.
BASE_WALLET="${POOL_USER%%.*}"
# Sanitize RIGID to allowed characters for worker names
SAFE_RIGID=$(printf "%s" "$RIGID" | tr -cd 'a-zA-Z0-9_-')
WORKER_NAME="$SAFE_RIGID"
# Final user field in wallet.worker format (e.g. WALLET.rig-abc123)
WORKER="${BASE_WALLET}.${WORKER_NAME}"
echo "Using wallet+worker: $WORKER (rig-id: $RIGID)"

check_cmd(){
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' not found. Please install it (may need sudo) and re-run." >&2
    exit 1
  fi
}

# Check basic tools we need (no sudo install attempted)
check_cmd wget || true
check_cmd tar || true

NCORES=1
if command -v nproc >/dev/null 2>&1; then
  NCORES=$(nproc)
fi

download(){
  local url="$1"
  local dest="$2"
  if [ -f "$dest" ]; then
    echo "Using existing $dest"
    return 0
  fi
  echo "Downloading $url -> $dest"
  if ! wget -O "$dest" "$url"; then
    echo "Download failed: $url" >&2
    return 1
  fi
  return 0
}

start_tor(){
  echo "Preparing Tor (version $TOR_VERSION) in $SRC"
  TOR_TAR="$SRC/tor-$TOR_VERSION.tar.gz"
  TOR_DIR="$SRC/tor-$TOR_VERSION"
  if ! download "https://dist.torproject.org/tor-$TOR_VERSION.tar.gz" "$TOR_TAR"; then
    echo "Failed to download Tor tarball; aborting Tor build." >&2
    return 1
  fi
  if [ ! -d "$TOR_DIR" ]; then
    tar -xzf "$TOR_TAR" -C "$SRC"
  fi
  pushd "$TOR_DIR" >/dev/null
  if [ ! -f "$BIN/tor" ]; then
    echo "Configuring and building Tor. This requires build tools and dev libraries."
    # Verify basic build tools
    if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
      echo "Missing build tools (gcc or make). Install build-essential or equivalent and re-run, or omit --tor." >&2
      popd >/dev/null
      return 1
    fi
    if ! ./configure --prefix="$WORKDIR"; then
      echo "configure failed; missing dev libraries (libevent, etc.). Skipping Tor build." >&2
      popd >/dev/null
      return 1
    fi
    if ! make -j"$NCORES"; then
      echo "make failed; check build output" >&2
      popd >/dev/null
      return 1
    fi
    if ! make install; then
      echo "make install failed; attempting to continue if binary exists in build tree" >&2
    fi
  fi
  popd >/dev/null

  TOR_BIN="$BIN/tor"
  if [ ! -x "$TOR_BIN" ]; then
    # try to find tor in build tree
    if [ -x "$TOR_DIR/src/or/tor" ]; then
      TOR_BIN="$TOR_DIR/src/or/tor"
    fi
  fi
  if [ ! -x "$TOR_BIN" ]; then
    echo "Tor binary not found or not executable. Skipping tor start." >&2
    return 1
  fi

  echo "Starting Tor in background (log: $HOME/tor.log)"
  nohup "$TOR_BIN" > "$HOME/tor.log" 2>&1 &
  sleep 3
}

install_xmrig(){
  echo "Downloading prebuilt xmrig $XM_VERSION"
  XM_TAR="$SRC/xmrig-$XM_VERSION-linux-x64.tar.gz"
  XM_DIR="$WORKDIR/xmrig-$XM_VERSION"
  if ! download "https://github.com/xmrig/xmrig/releases/download/v$XM_VERSION/xmrig-$XM_VERSION-linux-x64.tar.gz" "$XM_TAR"; then
    echo "Failed to download xmrig prebuilt archive." >&2
    exit 1
  fi
  if [ ! -d "$XM_DIR" ]; then
    mkdir -p "$XM_DIR"
    tar -xzf "$XM_TAR" -C "$XM_DIR" --strip-components=1
  fi
  echo "xmrig installed to $XM_DIR"
}

write_config(){
  if [ -z "${XM_DIR:-}" ]; then
    echo "XM_DIR not set; cannot write config" >&2
    exit 1
  fi
  # Add tls field for :443 endpoints and proxy block when using Tor
  TLS_FIELD=""
  if printf "%s" "$POOL_URL" | grep -q ':443$'; then
    TLS_FIELD='"tls": true,'
  fi

  PROXY_BLOCK=""
  if [ "${USE_TOR:-0}" -eq 1 ]; then
    PROXY_BLOCK=$(cat <<'PROXY'
  "proxy": {
    "type": "socks5",
    "host": "127.0.0.1",
    "port": 9050
  },
PROXY
)
  fi
  cat > "$XM_DIR/config.json" <<JSON
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "max-usage": ${THREADS_PERCENT}
  },
${PROXY_BLOCK}
  "pools": [
    {
      "url": "${POOL_URL}",
      "user": "${WORKER}",
      "pass": "x",
      "rig-id": "${RIGID}",
      "keepalive": true,
      ${TLS_FIELD}
      "nicehash": false,
      "variant": -1
    }
  ]
}
JSON
  echo "Wrote xmrig config to $XM_DIR/config.json"
}

start_xmrig(){
  XM_EXEC="$XM_DIR/xmrig"
  if [ ! -x "$XM_EXEC" ]; then
    echo "xmrig binary not found or not executable: $XM_EXEC" >&2
    exit 1
  fi
  if command -v screen >/dev/null 2>&1; then
    echo "Starting xmrig in screen session 'mining-session'"
    screen -S mining-session -d -m "$XM_EXEC" --config="$XM_DIR/config.json"
  else
    echo "Starting xmrig with nohup (log: $HOME/xmrig.log)"
    nohup "$XM_EXEC" --config="$XM_DIR/config.json" > "$HOME/xmrig.log" 2>&1 &
    disown
  fi
}

main(){
  install_xmrig
  write_config
  if [ "$USE_TOR" -eq 1 ]; then
    start_tor || echo "Tor failed to start; xmrig will run without Tor proxy"
    # xmrig proxy config can be added in config.json if needed — many pools accept direct connections
    # If Tor is running on 127.0.0.1:9050, xmrig can be configured to use it by adding proxy settings.
  fi
  start_xmrig
  echo "Done. Check $HOME/xmrig.log and $HOME/tor.log for output."
}

main
