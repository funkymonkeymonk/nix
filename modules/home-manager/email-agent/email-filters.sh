#!/usr/bin/env bash
# email-filters: Manage Gmail filters via gmailctl
#
# Usage:
#   email-filters list           # Show current filters
#   email-filters edit           # Open filter config in $EDITOR
#   email-filters diff           # Show pending filter changes
#   email-filters apply          # Apply filter changes to Gmail
#   email-filters export         # Export current Gmail filters
#   email-filters init           # First-time OAuth2 setup
#
# Filter config is in ~/__GMAILCTL_CONFIG_DIR__/config.jsonnet
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONFIG_DIR="$HOME/__GMAILCTL_CONFIG_DIR__"

ensure_config() {
  if [[ ! -f "$CONFIG_DIR/config.jsonnet" ]]; then
    echo -e "${YELLOW}No gmailctl config found at $CONFIG_DIR/config.jsonnet${NC}"
    echo -e "Run 'email-filters init' to set up gmailctl."
    return 1
  fi
}

usage() {
  cat <<EOF
Usage: email-filters <command>

Commands:
  list      Show current Gmail filters
  edit      Open filter config in \$EDITOR
  diff      Show pending filter changes (local vs Gmail)
  apply     Apply filter changes to Gmail
  export    Export current Gmail filters to local config
  init      First-time OAuth2 setup for gmailctl
  test      Validate filter config syntax

Filter config: $CONFIG_DIR/config.jsonnet

First-time setup:
  1. Run 'email-filters init' to authorize with Google
  2. Edit $CONFIG_DIR/config.jsonnet to define filters
  3. Run 'email-filters diff' to preview changes
  4. Run 'email-filters apply' to push to Gmail
EOF
  exit 1
}

case "${1:-}" in
  init)
    echo -e "${GREEN}Initializing gmailctl...${NC}"
    echo "This will open a browser for Google OAuth2 authorization."
    mkdir -p "$CONFIG_DIR"
    gmailctl init --config "$CONFIG_DIR"
    echo -e "${GREEN}Done. Edit $CONFIG_DIR/config.jsonnet to define filters.${NC}"
    ;;
  list)
    ensure_config || exit 1
    gmailctl list --config "$CONFIG_DIR"
    ;;
  edit)
    ensure_config || exit 1
    ${EDITOR:-vi} "$CONFIG_DIR/config.jsonnet"
    ;;
  diff)
    ensure_config || exit 1
    echo -e "${BLUE}Comparing local config with Gmail filters...${NC}"
    gmailctl diff --config "$CONFIG_DIR"
    ;;
  apply)
    ensure_config || exit 1
    echo -e "${YELLOW}Applying filter changes to Gmail...${NC}"
    gmailctl apply --config "$CONFIG_DIR"
    echo -e "${GREEN}Filters applied.${NC}"
    ;;
  export)
    mkdir -p "$CONFIG_DIR"
    echo -e "${BLUE}Exporting current Gmail filters...${NC}"
    gmailctl export --config "$CONFIG_DIR"
    echo -e "${GREEN}Exported to $CONFIG_DIR/${NC}"
    ;;
  test)
    ensure_config || exit 1
    gmailctl test --config "$CONFIG_DIR"
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    echo -e "${RED}Unknown command: $1${NC}"
    usage
    ;;
esac
