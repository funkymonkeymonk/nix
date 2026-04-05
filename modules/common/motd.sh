#!/usr/bin/env bash
# MOTD script - run directly for rapid testing: bash modules/common/motd.sh
#
# Configuration via environment variables (defaults shown):
#   MOTD_SHOW_HOSTNAME=1        Show username@hostname line
#   MOTD_SHOW_GIT_COMMIT=1      Show git revision line
#   MOTD_GITHUB_URL=...         GitHub repo URL for commit links
#   MOTD_EXTRA_MESSAGE=""       Extra message to display at bottom
set -euo pipefail

# Colors - using $'\033' syntax for reliable escape interpretation
ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
CYAN="${ESC}[36m"
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
MAGENTA="${ESC}[35m"
BLUE="${ESC}[34m"
ORANGE="${ESC}[38;5;208m"

# Symbols
GIT_SYM="📦"
CLOCK_SYM="⏱️"
TIME_SYM="🕐"
UPTIME_SYM="⚡"
WARNING_SYM="⚠️"
LINK_SYM="🔗"

# Configurable options (set via environment or defaults)
SHOW_HOSTNAME="${MOTD_SHOW_HOSTNAME:-1}"
SHOW_GIT_COMMIT="${MOTD_SHOW_GIT_COMMIT:-1}"
GITHUB_URL="${MOTD_GITHUB_URL:-https://github.com/funkymonkeymonk/nix}"
EXTRA_MESSAGE="${MOTD_EXTRA_MESSAGE:-}"

HOSTNAME=$(hostname -s 2>/dev/null || hostname)
USERNAME=$(whoami)
HOST_SEP="${DIM}@${RESET}"

# Git commit detection
GIT_SHA="unknown"
if [ -f /run/current-system/nix-support/system-config ]; then
  GIT_SHA=$(cat /run/current-system/nix-support/system-config 2>/dev/null | head -1)
elif [ -f /run/current-system/configuration-name ]; then
  GIT_SHA=$(cat /run/current-system/configuration-name 2>/dev/null)
elif [ -L /run/current-system ]; then
  GIT_SHA=$(basename "$(readlink -f /run/current-system)" 2>/dev/null | grep -oE '^[a-z0-9]{32}' | head -1)
fi

GIT_STATUS=""
if [ -n "$GIT_SHA" ] && [ "$GIT_SHA" != "unknown" ]; then
  SHORT_SHA=$(echo "$GIT_SHA" | cut -c1-8)
  COMMIT_URL="${GITHUB_URL}/commit/${GIT_SHA}"
  SHA_DISPLAY="${YELLOW}${LINK_SYM} ${SHORT_SHA}${RESET}"
  # OSC 8 hyperlink format - using $'\033' for escape
  SHA_LINK="${ESC}]8;;${COMMIT_URL}${ESC}\\${SHA_DISPLAY}${ESC}]8;;${ESC}\\"

  # Check if commit exists on GitHub via HTTPS API (no SSH required)
  if command -v curl &>/dev/null; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${COMMIT_URL}" 2>/dev/null || echo "000")
    if [ "$HTTP_STATUS" = "404" ]; then
      GIT_STATUS="unpushed"
    fi
  fi
else
  SHORT_SHA="unknown"
  SHA_LINK="${YELLOW}${SHORT_SHA}${RESET}"
fi

# System age detection
SYSTEM_EPOCH=""
if [ -f /run/current-system/init ]; then
  if command -v stat &>/dev/null; then
    SYSTEM_EPOCH=$(stat -c %Y /run/current-system/init 2>/dev/null || stat -f %m /run/current-system/init 2>/dev/null)
  fi
elif [ -d /run/current-system ]; then
  if command -v stat &>/dev/null; then
    SYSTEM_EPOCH=$(stat -c %Y /run/current-system 2>/dev/null || stat -f %m /run/current-system 2>/dev/null)
  fi
fi

AGE_STR="unknown"
AGE_SECONDS=0
if [ -n "$SYSTEM_EPOCH" ]; then
  CURRENT_EPOCH=$(date +%s)
  AGE_SECONDS=$((CURRENT_EPOCH - SYSTEM_EPOCH))
  days=$((AGE_SECONDS / 86400))
  hours=$(((AGE_SECONDS % 86400) / 3600))
  minutes=$(((AGE_SECONDS % 3600) / 60))

  if [ $days -gt 0 ]; then
    AGE_STR="${days}d ${hours}h ${minutes}m"
  elif [ $hours -gt 0 ]; then
    AGE_STR="${hours}h ${minutes}m"
  else
    AGE_STR="${minutes}m"
  fi
fi

# Get system info
CURRENT_TIME_STR=$(date +"%H:%M:%S")
UPTIME_STR="unknown"

if command -v uptime &>/dev/null; then
  UPTIME_RAW=$(uptime)
  # Parse uptime differently for macOS vs Linux
  if echo "$UPTIME_RAW" | grep -q "load average"; then
    # macOS format: "13:38:12  up 18 days 13:15,  6 users,  load average: 4.37, 3.73, 3.68"
    # Extract just the uptime duration between "up " and ","
    UPTIME_STR=$(echo "$UPTIME_RAW" | sed 's/.*up *\([^,]*\),.*/\1/' | sed 's/ *$//')
  else
    # Linux format or fallback
    UPTIME_STR=$(echo "$UPTIME_RAW" | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' | sed 's/ *$//')
  fi
fi

# Image handling
CACHE_DIR="$HOME/.cache/motd"
IMAGE_FILE="$CACHE_DIR/daily.jpg"
STAMP_FILE="$CACHE_DIR/timestamp"

# Create cache directory
mkdir -p "$CACHE_DIR"

# Check if we need a new image (once per day)
NEEDS_FETCH=1
if [ -f "$STAMP_FILE" ] && [ -f "$IMAGE_FILE" ]; then
  LAST_FETCH=$(cat "$STAMP_FILE" 2>/dev/null || echo 0)
  CURRENT_DAY=$(date +%Y%m%d)
  if [ "$LAST_FETCH" = "$CURRENT_DAY" ]; then
    NEEDS_FETCH=0
  fi
fi

# Fetch new random image if needed
if [ $NEEDS_FETCH -eq 1 ]; then
  # Try to fetch a random image from Picsum
  if curl -sL "https://picsum.photos/200/200" -o "$IMAGE_FILE.tmp" 2>/dev/null; then
    mv "$IMAGE_FILE.tmp" "$IMAGE_FILE"
    date +%Y%m%d > "$STAMP_FILE"
  else
    # If fetch fails, keep old image or continue without image
    rm -f "$IMAGE_FILE.tmp"
  fi
fi

WIDTH=50
LINE=$(printf '%*s' $WIDTH ' ' | tr ' ' '-')

# Push prior terminal output into scrollback, then clear
# This ensures "Last login" and shell init messages are scrollable
TERM_LINES=$(tput lines 2>/dev/null || echo 24)
for _ in $(seq 1 "$TERM_LINES"); do printf '\n'; done
printf '%b' "${ESC}[H${ESC}[J"

# Image on left, text on right side-by-side
TEXT_COL=18
IMAGE_ROWS=8
if [ -f "$IMAGE_FILE" ] && command -v chafa &>/dev/null; then
  chafa --size=16x8 "$IMAGE_FILE" 2>/dev/null || true
  SHOWING_IMAGE=1
else
  SHOWING_IMAGE=0
  TEXT_COL=2
fi

# Helper: print text at absolute row/col
print_at() {
  local row=$1 col=$2 text=$3
  printf "${ESC}[${row};${col}H%s" "$text"
}

# Calculate starting row (row 1, top of cleared screen)
START_ROW=1

# username@hostname (conditional)
if [ "$SHOW_HOSTNAME" = "1" ]; then
  ROW=$START_ROW
  if [ "$SHOWING_IMAGE" = "1" ]; then
    print_at $ROW $((TEXT_COL + 6)) "${BOLD}${GREEN}${USERNAME}${HOST_SEP}${HOSTNAME}${RESET}"
  else
    printf "  %s\n" "${BOLD}${GREEN}${USERNAME}${HOST_SEP}${HOSTNAME}${RESET}"
  fi
  START_ROW=$((START_ROW + 1))
fi

# Git commit (conditional)
if [ "$SHOW_GIT_COMMIT" = "1" ] && [ "$SHORT_SHA" != "unknown" ]; then
  ROW=$START_ROW
  if [ "$GIT_STATUS" = "unpushed" ]; then
    TEXT="  ${YELLOW}${GIT_SYM}${RESET}  ${BOLD}Revision:${RESET} ${SHA_LINK} ${ORANGE}${WARNING_SYM} unpushed${RESET}"
  else
    TEXT="  ${YELLOW}${GIT_SYM}${RESET}  ${BOLD}Revision:${RESET} ${SHA_LINK}"
  fi
  if [ "$SHOWING_IMAGE" = "1" ]; then
    print_at $ROW $TEXT_COL "$TEXT"
  else
    printf "%b\n" "$TEXT"
  fi
  START_ROW=$((START_ROW + 1))
fi

# Age
if [ "$AGE_STR" != "unknown" ]; then
  if [ $AGE_SECONDS -lt 3600 ]; then
    AGE_COLOR="$GREEN"
  elif [ $AGE_SECONDS -lt 86400 ]; then
    AGE_COLOR="$YELLOW"
  else
    AGE_COLOR="$ORANGE"
  fi
  ROW=$START_ROW
  TEXT="  ${BLUE}${CLOCK_SYM}${RESET}  ${BOLD}Age:${RESET}      ${AGE_COLOR}${AGE_STR}${RESET} ${DIM}since last switch${RESET}"
  if [ "$SHOWING_IMAGE" = "1" ]; then
    print_at $ROW $TEXT_COL "$TEXT"
  else
    printf "%b\n" "$TEXT"
  fi
  START_ROW=$((START_ROW + 1))
fi

# Time
ROW=$START_ROW
TEXT="  ${CYAN}${TIME_SYM}${RESET}  ${BOLD}Time:${RESET}     ${CYAN}${CURRENT_TIME_STR}${RESET}"
if [ "$SHOWING_IMAGE" = "1" ]; then
  print_at $ROW $TEXT_COL "$TEXT"
else
  printf "%b\n" "$TEXT"
fi
START_ROW=$((START_ROW + 1))

# Uptime
ROW=$START_ROW
TEXT="  ${GREEN}${UPTIME_SYM}${RESET}  ${BOLD}Uptime:${RESET}   ${GREEN}${UPTIME_STR}${RESET}"
if [ "$SHOWING_IMAGE" = "1" ]; then
  print_at $ROW $TEXT_COL "$TEXT"
else
  printf "%b\n" "$TEXT"
fi
START_ROW=$((START_ROW + 1))

# Weather
WEATHER=""
if command -v curl &>/dev/null; then
  WEATHER=$(curl -s "wttr.in?format=%c+%t+%h+%w" --max-time 3 2>/dev/null || true)
fi
if [ -n "$WEATHER" ]; then
  ROW=$START_ROW
  TEXT="  ${MAGENTA}🌤️${RESET}  ${BOLD}Weather:${RESET}  ${MAGENTA}${WEATHER}${RESET}"
  if [ "$SHOWING_IMAGE" = "1" ]; then
    print_at $ROW $TEXT_COL "$TEXT"
  else
    printf "%b\n" "$TEXT"
  fi
  START_ROW=$((START_ROW + 1))
fi

# Dad joke
DAD_JOKE=""
if command -v curl &>/dev/null; then
  DAD_JOKE=$(curl -s -H "Accept: text/plain" https://icanhazdadjoke.com/ --max-time 3 2>/dev/null || true)
fi
if [ -n "$DAD_JOKE" ]; then
  ROW=$START_ROW
  TEXT="  ${YELLOW}😄${RESET}  ${BOLD}Joke:${RESET}  ${DIM}${DAD_JOKE}${RESET}"
  if [ "$SHOWING_IMAGE" = "1" ]; then
    print_at $ROW $TEXT_COL "$TEXT"
  else
    printf "%b\n" "$TEXT"
  fi
  START_ROW=$((START_ROW + 1))
fi

# Extra message block (conditional)
if [ -n "$EXTRA_MESSAGE" ]; then
  ROW=$((START_ROW + 1))
  if [ "$SHOWING_IMAGE" = "1" ]; then
    print_at $ROW $TEXT_COL "  ${DIM}${LINE}${RESET}"
    print_at $((ROW + 1)) $TEXT_COL "  ${EXTRA_MESSAGE}"
  else
    printf "\n"
    printf "  %b%s%b\n" "$DIM" "$LINE" "$RESET"
    printf "  %s\n" "$EXTRA_MESSAGE"
  fi
  START_ROW=$((START_ROW + 2))
fi

# Move cursor below the image/text area
if [ "$SHOWING_IMAGE" = "1" ]; then
  FINAL_ROW=$((START_ROW > IMAGE_ROWS ? START_ROW : IMAGE_ROWS))
  printf "%s" "${ESC}[$((FINAL_ROW + 1));1H"
fi

# Final newline
printf "\n"
