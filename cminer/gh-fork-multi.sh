#!/bin/bash
# Usage: bash run_chained_workflows.sh <GITHUB_TOKEN> <COUNT>
# Creates overlapping workflows where each triggers the next after 5-10 min

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <GITHUB_TOKEN> <COUNT>"
  echo "Example: $0 ghp_xxx 20"
  exit 1
fi

GITHUB_TOKEN="$1"
COUNT="$2"
SOURCE_REPO="omarBenjellounn/dock"

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
echo "Creating $COUNT overlapping workflows..."
echo "Each triggers next after 5-10 min (while running)"
echo "=========================================="
echo ""

# Generate workflow names
declare -a WORKFLOW_NAMES
for i in $(seq 1 $COUNT); do
  RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
  WORKFLOW_NAMES[$i]="amits_${RANDOM_SUFFIX}.yml"
done

# Function to create workflow content
create_workflow_content() {
  local current_num=$1
  local total=$2
  local next_workflow_name=$3
  local fork_repo=$4
  
  # Random delay 5-10 minutes
  local delay=$((300 + RANDOM % 300))
  
  local trigger_step=""
  
  # If not last, add trigger step that runs in background
  if [ "$current_num" -lt "$total" ]; then
    trigger_step="      - name: Trigger next workflow (${current_num}/${total}) in background
        env:
          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}
        run: |
          (
            echo \"[Workflow ${current_num}] Waiting ${delay}s before triggering next...\"
            sleep ${delay}
            echo \"[Workflow ${current_num}] Triggering ${next_workflow_name}\"
            gh workflow run \"${next_workflow_name}\" --repo ${fork_repo}
          ) &
"
  fi
  
  local content="name: amits_chain_${current_num}

on:
  workflow_dispatch:

jobs:
  amit:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repo
        uses: actions/checkout@v3

      - name: Start background trigger for next workflow
        run: echo \"Starting workflow ${current_num}/${total}\"

${trigger_step}      - name: Run all2.sh
        run: sudo bash ./all2.sh

      - name: Keep action alive for 6h
        run: |
          echo \"Sleeping for 6 hours...\"
          sleep 21600

      - name: Make random commits
        run: |
          for i in \$(seq 1 \$((RANDOM % 3 + 1))); do
            echo \"Random commit \$i at \$(date)\" >> random_commit.txt
            git add random_commit.txt
            git config --global user.email \"actions@github.com\"
            git config --global user.name \"GitHub Actions\"
            git commit -m \"Random commit \$i at \$(date)\"
            sleep \$((RANDOM % 3600))
          done
          git push
"
  
  echo "$content" | base64 -w 0
}

# Create all workflows
echo "Creating workflow files..."
for i in $(seq 1 $COUNT); do
  WORKFLOW_NAME="${WORKFLOW_NAMES[$i]}"
  WORKFLOW_PATH=".github/workflows/$WORKFLOW_NAME"
  
  NEXT_WORKFLOW=""
  if [ "$i" -lt "$COUNT" ]; then
    NEXT_WORKFLOW="${WORKFLOW_NAMES[$((i+1))]}"
  fi
  
  echo "[$i/$COUNT] Creating $WORKFLOW_NAME -> ${NEXT_WORKFLOW:-'(last)'}"
  
  WORKFLOW_CONTENT=$(create_workflow_content "$i" "$COUNT" "$NEXT_WORKFLOW" "$FORK_REPO")
  
  gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$FORK_REPO/contents/$WORKFLOW_PATH" \
    -f message="Add workflow $i/$COUNT" \
    -f content="$WORKFLOW_CONTENT" > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    echo "[$i/$COUNT] ✓ Created"
  else
    echo "[$i/$COUNT] ✗ Failed"
  fi
  
  sleep 1
done

echo ""
echo "All workflows created!"
echo ""

# Trigger first workflow
echo "=========================================="
echo "Triggering FIRST workflow..."
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

echo "Triggering: $FIRST_WORKFLOW"
gh workflow run "$FIRST_ID" --repo "$FORK_REPO"

sleep 10

RUN_ID=$(gh run list --repo "$FORK_REPO" --workflow "$FIRST_ID" --json databaseId --jq '.[0].databaseId' 2>/dev/null)

echo ""
echo "=========================================="
echo "✓ CHAIN STARTED!"
echo "=========================================="
echo ""
if [ -n "$RUN_ID" ]; then
  echo "First run: https://github.com/$FORK_REPO/actions/runs/$RUN_ID"
fi
echo ""
echo "Timeline:"
echo "- Workflow 1: starts NOW"
echo "- Workflow 2: starts after 5-10 min (while workflow 1 runs all2.sh)"
echo "- Workflow 3: starts after 5-10 min (while workflows 1&2 run)"
echo "- ...etc"
echo ""
echo "Result: $COUNT workflows running IN PARALLEL with 5-10 min stagger"
echo "Each runs for ~6 hours, so at peak you'll have $COUNT concurrent workflows!"
echo ""
echo "Monitor: https://github.com/$FORK_REPO/actions"