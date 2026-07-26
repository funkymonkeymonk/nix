#!/usr/bin/env bash
# email-backup-restore: Search and restore from encrypted email backups
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

RESTIC_REPO="__RESTIC_REPO_PATH__"
RESTIC_PASSWORD_FILE="__RESTIC_PASSWORD_PATH__"
MAILDIR="__MAILDIR_PATH__"

check_repo() {
  if [[ ! -f "$RESTIC_PASSWORD_FILE" ]]; then
    echo -e "${RED}Restic password file not found. Run 'email-backup-setup' first.${NC}"
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: email-backup-restore <command> [args]

Commands:
  list                           List all backup snapshots
  search <notmuch-query>         Search the current backup index
  mount <mountpoint>             Mount backup snapshots (FUSE) for browsing
  restore <snapshot-id> <dest>   Restore a snapshot to a directory
  diff <snap1> <snap2>           Show what changed between two snapshots
  stats                          Show backup repository statistics

Examples:
  email-backup-restore list
  email-backup-restore search "from:important@client.com"
  email-backup-restore search "date:2026-04-01..2026-04-14 AND tag:inbox"
  email-backup-restore mount /tmp/mail-restore
  email-backup-restore restore latest ~/recovered-mail
  email-backup-restore diff abc123 def456
EOF
  exit 1
}

case "${1:-}" in
  list)
    check_repo
    echo -e "${BLUE}Backup snapshots:${NC}"
    restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" \
      snapshots --tag email
    ;;

  search)
    shift
    if [[ $# -eq 0 ]]; then
      echo -e "${RED}Usage: email-backup-restore search <notmuch-query>${NC}"
      exit 1
    fi
    QUERY="$*"
    if [[ ! -d "$MAILDIR/.notmuch" ]]; then
      echo -e "${YELLOW}Notmuch database not found. Run 'email-backup' first.${NC}"
      exit 1
    fi
    echo -e "${BLUE}Searching backup index for: $QUERY${NC}"
    NOTMUCH_CONFIG="$HOME/.notmuch-config-backup" notmuch search "$QUERY"
    ;;

  show)
    shift
    if [[ $# -eq 0 ]]; then
      echo -e "${RED}Usage: email-backup-restore show <notmuch-query>${NC}"
      exit 1
    fi
    QUERY="$*"
    if [[ ! -d "$MAILDIR/.notmuch" ]]; then
      echo -e "${YELLOW}Notmuch database not found. Run 'email-backup' first.${NC}"
      exit 1
    fi
    NOTMUCH_CONFIG="$HOME/.notmuch-config-backup" notmuch show "$QUERY"
    ;;

  mount)
    check_repo
    MOUNTPOINT="${2:-/tmp/email-backup-restore}"
    mkdir -p "$MOUNTPOINT"
    echo -e "${GREEN}Mounting backup snapshots at $MOUNTPOINT${NC}"
    echo -e "Browse: $MOUNTPOINT/snapshots/<date>/..."
    echo -e "Press Ctrl+C to unmount."
    restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" \
      mount "$MOUNTPOINT"
    ;;

  restore)
    check_repo
    SNAPSHOT="${2:-latest}"
    DEST="${3:-$HOME/recovered-mail}"
    mkdir -p "$DEST"
    echo -e "${GREEN}Restoring snapshot $SNAPSHOT to $DEST...${NC}"
    restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" \
      restore "$SNAPSHOT" --target "$DEST" --tag email
    echo -e "${GREEN}Restored to $DEST${NC}"
    ;;

  diff)
    check_repo
    if [[ $# -lt 3 ]]; then
      echo -e "${RED}Usage: email-backup-restore diff <snapshot1> <snapshot2>${NC}"
      exit 1
    fi
    restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" \
      diff "$2" "$3"
    ;;

  stats)
    check_repo
    echo -e "${BLUE}Backup repository statistics:${NC}"
    restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" \
      stats --tag email
    echo ""
    echo -e "${BLUE}Snapshot count:${NC}"
    restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" \
      snapshots --tag email --compact | tail -1
    ;;

  -h|--help|"")
    usage
    ;;

  *)
    echo -e "${RED}Unknown command: $1${NC}"
    usage
    ;;
esac
