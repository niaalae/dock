#!/usr/bin/env bash
set -euo pipefail

# Template: create a GitHub Codespace and run a command inside it using the GitHub CLI
# IMPORTANT: Do NOT hardcode your PAT/token in this file. Set GITHUB_TOKEN in your environment.
# This script is a template — verify `gh` flags available in your `gh` version before use.

REPO=""           # owner/repo (e.g. myorg/myrepo) - required
REF="main"        # branch/ref
MACHINE="standardLinux32gb"
LOCATION="UsWest"
SETUP_CMD="sudo ./setup.sh"

usage() {
  cat <<EOF
Usage: $0 <owner/repo> <setup-key>

Creates a Codespace for the given repository (branch=${REF}, machine=${MACHINE}, location=${LOCATION})
and runs the setup command inside it.

You must set the environment variable GITHUB_TOKEN or run 'gh auth login' before running this.
Example:
  export GITHUB_TOKEN=your_token_here
  $0 owner/repo 49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F

The script will not store your token. Revoke any token you already exposed publicly.
EOF
}

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ]; then
  usage
  exit 1
fi

REPO="$1"
KEY="$2"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh (GitHub CLI) is required. Install from https://cli.github.com/"
  exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "GITHUB_TOKEN is not set. Use 'gh auth login' or export GITHUB_TOKEN before running."
  exit 1
fi

echo "Authenticating gh CLI using GITHUB_TOKEN (non-interactive)..."
echo "$GITHUB_TOKEN" | gh auth login --with-token || true

echo "Creating Codespace for ${REPO} (ref=${REF}, machine=${MACHINE}, location=${LOCATION})..."

# Attempt to create a codespace. This uses `gh codespace create` if available.
# Flags for gh may differ across versions; this is a best-effort template.
set +e
CS_OUT=$(gh codespace create --repo "$REPO" --ref "$REF" --machine "$MACHINE" --location "$LOCATION" 2>&1)
CS_EXIT=$?
set -e

if [ $CS_EXIT -ne 0 ]; then
  echo "Failed to create codespace. Output:" >&2
  echo "$CS_OUT" >&2
  echo "Check your gh version and permissions. Aborting." >&2
  exit $CS_EXIT
fi

echo "Codespace create output:"
echo "$CS_OUT"

# Try to extract the codespace name. If gh printed a name line, try to find it.
CS_NAME=$(printf "%s" "$CS_OUT" | awk '/^Created codespace/ {print $3; exit} { if ($0 ~ /name:/) {print $2; exit}}')

if [ -z "$CS_NAME" ]; then
  echo "Could not determine codespace name from output. Please run 'gh codespace list' to find it." >&2
  exit 1
fi

echo "Using codespace name: $CS_NAME"

FULL_CMD="$SETUP_CMD $KEY \"\$(hostname)\" 85"
echo "Running setup inside codespace: $FULL_CMD"

# Run the command inside the codespace. This uses `gh codespace exec` if available.
exec_out=$(gh codespace exec --codespace "$CS_NAME" --command "$FULL_CMD" 2>&1) || true
exec_status=$?

echo "Command output:"
echo "$exec_out"

if [ $exec_status -ne 0 ]; then
  echo "Command inside codespace exited with status $exec_status" >&2
  exit $exec_status
fi

echo "Done."
