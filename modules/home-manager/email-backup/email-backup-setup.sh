#!/usr/bin/env bash
# email-backup-setup: Initialize the email backup infrastructure
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

MAILDIR="__MAILDIR_PATH__"
RESTIC_REPO="__RESTIC_REPO_PATH__"
RESTIC_PASSWORD_FILE="__RESTIC_PASSWORD_PATH__"

echo -e "${GREEN}=== Email Backup Setup ===${NC}"
echo ""

# 1. Create directories
echo -e "${BLUE}Creating directories...${NC}"
mkdir -p "$MAILDIR"
mkdir -p "$(dirname "$RESTIC_REPO")"
mkdir -p "$(dirname "$RESTIC_PASSWORD_FILE")"

# 2. Generate restic password if needed
if [[ ! -f "$RESTIC_PASSWORD_FILE" ]]; then
  echo -e "${BLUE}Generating restic repository password...${NC}"
  head -c 32 /dev/urandom | base64 > "$RESTIC_PASSWORD_FILE"
  chmod 600 "$RESTIC_PASSWORD_FILE"
  echo -e "${YELLOW}IMPORTANT: Back up this password file!${NC}"
  echo -e "  $RESTIC_PASSWORD_FILE"
  echo -e "  Without it, your backups are unrecoverable."
else
  echo "  Restic password file already exists."
fi

# 3. Initialize restic repo if needed
if [[ ! -d "$RESTIC_REPO" ]] || ! restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" cat config &>/dev/null; then
  echo -e "${BLUE}Initializing restic repository...${NC}"
  restic -r "$RESTIC_REPO" --password-file "$RESTIC_PASSWORD_FILE" init
else
  echo "  Restic repository already initialized."
fi

# 4. Initialize notmuch if needed
if [[ ! -d "$MAILDIR/.notmuch" ]]; then
  echo -e "${BLUE}Initializing notmuch database...${NC}"

  cat > "$HOME/.notmuch-config-backup" << 'NOTMUCH_EOF'
__NOTMUCH_CONFIG__
NOTMUCH_EOF

  NOTMUCH_CONFIG="$HOME/.notmuch-config-backup" notmuch new
else
  echo "  Notmuch database already initialized."
fi

# 5. Check mbsync password
if [[ ! -f "$HOME/.mbsync-passwd" ]]; then
  echo ""
  echo -e "${YELLOW}ACTION REQUIRED: Set up Gmail App Password${NC}"
  echo "  1. Enable 2FA on your Google account"
  echo "  2. Go to https://myaccount.google.com/apppasswords"
  echo "  3. Create an App Password for 'Mail'"
  echo "  4. Run: echo 'your-app-password' > ~/.mbsync-passwd && chmod 600 ~/.mbsync-passwd"
else
  echo "  mbsync password file exists."
fi

echo ""
echo -e "${GREEN}Setup complete. Run 'email-backup' to perform first backup.${NC}"
