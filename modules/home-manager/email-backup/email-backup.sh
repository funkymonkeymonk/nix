#!/usr/bin/env bash
# email-backup: Pull mail, index, snapshot to restic
set -euo pipefail

LOG_FILE="/tmp/email-backup.log"
LOCK_FILE="/tmp/email-backup.lock"
MAILDIR="__MAILDIR_PATH__"
ACCOUNT_MAILDIR="__ACCOUNT_MAILDIR__"
RESTIC_REPO="__RESTIC_REPO_PATH__"
RESTIC_PASSWORD_FILE="__RESTIC_PASSWORD_PATH__"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Acquire exclusive lock (fail immediately if another backup is running)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "SKIPPED: Another backup is already running (lock held on $LOCK_FILE)"
  exit 0
fi
# Lock is released automatically when the script exits (fd 9 closes)

# Preflight checks
if [[ ! -f "$RESTIC_PASSWORD_FILE" ]]; then
  log "ERROR: Restic password file not found. Run 'email-backup-setup' first."
  exit 1
fi

if [[ ! -f "$HOME/.mbsync-passwd" ]]; then
  log "ERROR: mbsync password not found. See 'email-backup-setup' for instructions."
  exit 1
fi

# Ensure directories exist
mkdir -p "$ACCOUNT_MAILDIR"

# Initialize restic repo if needed (handles first run)
if ! restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" cat config &>/dev/null; then
  log "Initializing restic repository..."
  restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" init
fi

# Initialize notmuch if needed
if [[ ! -d "$MAILDIR/.notmuch" ]]; then
  log "Initializing notmuch..."
  email-backup-setup
fi

# 1. Pull mail from Gmail (read-only)
log "Pulling mail from __ACCOUNT_NAME__..."
if mbsync --config "$HOME/.mbsyncrc-backup" __ACCOUNT_NAME__; then
  log "mbsync pull completed"
else
  log "ERROR: mbsync failed"
  exit 1
fi

# 2. Index with notmuch
log "Indexing with notmuch..."
NOTMUCH_CONFIG="$HOME/.notmuch-config-backup" notmuch new

# 3. Snapshot to restic
log "Creating restic snapshot..."
if restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" \
  backup "$MAILDIR" \
  --tag email --tag "__ACCOUNT_NAME__" \
  --exclude '.notmuch/xapian/flintlock' \
  --exclude '.notmuch/xapian/postlist.*tmp' \
  2>> "$LOG_FILE"; then
  log "Restic snapshot created"
else
  log "ERROR: Restic backup failed"
  exit 1
fi

# 4. Prune old snapshots (keep hourly for 7 days, daily for __RETENTION_DAYS__ days)
log "Pruning old snapshots..."
restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" \
  forget --tag email \
  --keep-hourly 168 \
  --keep-daily __RETENTION_DAYS__ \
  --prune 2>> "$LOG_FILE" || log "WARNING: Prune had errors"

log "Backup complete"
