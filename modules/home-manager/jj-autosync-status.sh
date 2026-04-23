#!/usr/bin/env bash
# jj-autosync-status: Show status and logs for jj-autosync services
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== jj-autosync Status ===${NC}"
echo ""

# Show session status
echo -e "${BLUE}Active Sessions:${NC}"
jj-workspace-session status 2>/dev/null || echo "  (session manager not available)"
echo ""

# Show recent logs
echo -e "${BLUE}Recent Hourly Sync Log:${NC}"
if [[ -f /tmp/jj-autosync.log ]]; then
    tail -20 /tmp/jj-autosync.log
else
    echo "  (no log file)"
fi
echo ""

echo -e "${BLUE}Recent Fast Sync Log:${NC}"
if [[ -f /tmp/jj-fast-sync.log ]]; then
    tail -20 /tmp/jj-fast-sync.log
else
    echo "  (no log file)"
fi
