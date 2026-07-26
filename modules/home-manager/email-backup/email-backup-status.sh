#!/usr/bin/env bash
# email-backup-status: Show backup health and stats
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

MAILDIR="__MAILDIR_PATH__"
RESTIC_REPO="__RESTIC_REPO_PATH__"
RESTIC_PASSWORD_FILE="__RESTIC_PASSWORD_PATH__"

echo -e "${GREEN}=== Email Backup Status ===${NC}"
echo ""

# Staging maildir
echo -e "${BLUE}Staging Maildir:${NC} $MAILDIR"
if [[ -d "$MAILDIR" ]]; then
  msg_count=$(find "$MAILDIR" -type f -name '*:2,*' -o -name 'tmp' -prune 2>/dev/null | grep -c ':2,' || echo "0")
  echo "  Messages: ~$msg_count"
else
  echo -e "  ${YELLOW}Not yet created. Run 'email-backup-setup' first.${NC}"
fi
echo ""

# Notmuch index
echo -e "${BLUE}Search index:${NC}"
if [[ -d "$MAILDIR/.notmuch" ]]; then
  total=$(NOTMUCH_CONFIG="$HOME/.notmuch-config-backup" notmuch count '*' 2>/dev/null || echo "?")
  echo "  Indexed messages: $total"
else
  echo "  Not initialized"
fi
echo ""

# Restic repo
echo -e "${BLUE}Restic repository:${NC} $RESTIC_REPO"
if [[ -f "$RESTIC_PASSWORD_FILE" ]] && restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" cat config &>/dev/null 2>&1; then
  snap_count=$(restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" snapshots --tag email --json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
  echo "  Snapshots: $snap_count"

  latest=$(restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" snapshots --tag email --latest 1 --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['time'][:19] if d else 'never')" 2>/dev/null || echo "?")
  echo "  Latest snapshot: $latest"

  size=$(restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" stats --tag email --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('total_size',0)/1024/1024:.1f} MB\")" 2>/dev/null || echo "?")
  echo "  Total size: $size"
else
  echo -e "  ${YELLOW}Not initialized. Run 'email-backup-setup' first.${NC}"
fi
echo ""

# Backup schedule
echo -e "${BLUE}Backup schedule:${NC} every __BACKUP_INTERVAL_MINUTES__ minutes"
echo "  Retention: hourly for 7 days, daily for __RETENTION_DAYS__ days"
echo ""

# Recent log
echo -e "${BLUE}Recent backup log:${NC}"
if [[ -f /tmp/email-backup.log ]]; then
  tail -10 /tmp/email-backup.log
else
  echo "  (no log file)"
fi
