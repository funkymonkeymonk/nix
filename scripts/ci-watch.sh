#!/usr/bin/env bash
set -e

# Support both positional arg and env var for devenv task compatibility
RUN_ID="${1:-${CI_RUN_ID:-}}"
REPO="${CI_REPO:-funkymonkeymonk/nix}"

if [ -z "$RUN_ID" ]; then
  echo "Error: Run ID required"
  echo ""
  echo "Usage:"
  echo "  CI_RUN_ID=<id> devenv tasks run ci:watch"
  echo "  ./scripts/ci-watch.sh <run-id>"
  echo ""
  echo "To get the run ID for current branch:"
  BRANCH=$(jj bookmark list -r @ 2>/dev/null | head -1 | awk '{print $1}' || git branch --show-current 2>/dev/null || echo "main")
  echo "  gh run list --branch $BRANCH --limit 1 --json databaseId --repo $REPO | jq -r '.[0].databaseId'"
  exit 1
fi

# Colors for output
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Get initial run info
RUN_DATA=$(gh run view "$RUN_ID" --repo "$REPO" --json status,conclusion,url 2>/dev/null || echo '')
if [ -z "$RUN_DATA" ]; then
  echo -e "${RED}Error: Could not find run $RUN_ID${NC}"
  exit 1
fi

RUN_URL=$(echo "$RUN_DATA" | jq -r '.url')
INITIAL_STATUS=$(echo "$RUN_DATA" | jq -r '.status')

if [ "$INITIAL_STATUS" = "completed" ]; then
  CONCLUSION=$(echo "$RUN_DATA" | jq -r '.conclusion')
  echo -e "${GREEN}✓ CI already completed: $CONCLUSION${NC}"
  echo "  $RUN_URL"
  [ "$CONCLUSION" = "success" ] && exit 0 || exit 1
fi

echo -e "${BLUE}→ Watching CI run $RUN_ID${NC}"
echo "  $RUN_URL"
echo ""

# Polling: exponential backoff 15s → 45s
INTERVAL=15
START=$(date +%s)
COUNT=0

while true; do
  COUNT=$((COUNT + 1))
  NOW=$(date +%s)
  MIN=$(( (NOW - START) / 60 ))

  DATA=$(gh run view "$RUN_ID" --repo "$REPO" --json status,conclusion,jobs 2>/dev/null || echo '')
  STATUS=$(echo "$DATA" | jq -r '.status')

  if [ "$STATUS" = "in_progress" ]; then
    JOB=$(echo "$DATA" | jq -r '.jobs[] | select(.status == "in_progress") | .name' | head -1)
    [ -n "$JOB" ] && echo -e "${BLUE}[$COUNT, ${MIN}m] Running: $JOB${NC}" || echo -e "${BLUE}[$COUNT, ${MIN}m] In progress...${NC}"
  fi

  if [ "$STATUS" = "completed" ]; then
    CONCLUSION=$(echo "$DATA" | jq -r '.conclusion')
    echo ""
    if [ "$CONCLUSION" = "success" ]; then
      echo -e "${GREEN}✓ Success (${MIN}m)${NC}"
      exit 0
    else
      echo -e "${RED}✗ Failed: $CONCLUSION${NC}"
      echo "  gh run view $RUN_ID --repo $REPO --log"
      exit 1
    fi
  fi

  [ "$INTERVAL" -lt 45 ] && INTERVAL=$((INTERVAL + 10))
  sleep "$INTERVAL"
done
