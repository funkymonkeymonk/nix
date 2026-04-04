{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.motd;

  colors = {
    reset = "\\033[0m";
    bold = "\\033[1m";
    dim = "\\033[2m";
    cyan = "\\033[36m";
    green = "\\033[32m";
    yellow = "\\033[33m";
    magenta = "\\033[35m";
    blue = "\\033[34m";
    orange = "\\033[38;5;208m";
  };

  symbols = {
    nix = "❄️";
    git = "📦";
    clock = "⏱️";
    uptime = "⚡";
    link = "🔗";
  };

  hostnameLine = optionalString cfg.showHostname ''
    printf "  %b%b%b  %bHost:%b     %b%s%b\n" "${colors.cyan}" "▸" "${colors.reset}" "${colors.bold}" "${colors.reset}" "${colors.green}" "$HOSTNAME" "${colors.reset}"
  '';

  systemLine = optionalString cfg.showSystem ''
    printf "  %b%b%b  %bSystem:%b   %b%s%b (%b%s%b)\n" "${colors.cyan}" "▸" "${colors.reset}" "${colors.bold}" "${colors.reset}" "${colors.magenta}" "$OS_TYPE" "${colors.reset}" "${colors.dim}" "$SYSTEM" "${colors.reset}"
  '';

  extraMessageBlock = optionalString (cfg.extraMessage != "") ''
    printf "\n"
    printf "  %b%s%b\n" "${colors.dim}" "$LINE" "${colors.reset}"
    printf "  %s\n" "${cfg.extraMessage}"
  '';

  gitCommitLine = optionalString cfg.showGitCommit ''
    if [ "$SHORT_SHA" != "unknown" ]; then
      printf "  %b%b%b  %bRevision:%b %b\n" "${colors.yellow}" "${symbols.git}" "${colors.reset}" "${colors.bold}" "${colors.reset}" "$SHA_LINK"
    fi
  '';

  motdScriptText = ''
    set -euo pipefail

    RESET="${colors.reset}"
    BOLD="${colors.bold}"
    DIM="${colors.dim}"
    CYAN="${colors.cyan}"
    GREEN="${colors.green}"
    YELLOW="${colors.yellow}"
    MAGENTA="${colors.magenta}"
    BLUE="${colors.blue}"
    ORANGE="${colors.orange}"

    NIX_SYM="${symbols.nix}"
    GIT_SYM="${symbols.git}"
    CLOCK_SYM="${symbols.clock}"
    UPTIME_SYM="${symbols.uptime}"
    LINK_SYM="${symbols.link}"

    GITHUB_URL="${cfg.githubUrl}"

    HOSTNAME=$(hostname -s 2>/dev/null || hostname)
    SYSTEM="${pkgs.stdenv.hostPlatform.system}"
    OS_TYPE="${
      if pkgs.stdenv.hostPlatform.isDarwin
      then "macOS"
      else "NixOS"
    }"

    GIT_SHA="unknown"
    if [ -f /run/current-system/nix-support/system-config ]; then
      GIT_SHA=$(cat /run/current-system/nix-support/system-config 2>/dev/null | head -1)
    elif [ -f /run/current-system/configuration-name ]; then
      GIT_SHA=$(cat /run/current-system/configuration-name 2>/dev/null)
    elif [ -L /run/current-system ]; then
      GIT_SHA=$(basename "$(readlink -f /run/current-system)" 2>/dev/null | grep -oE '^[a-z0-9]\{32\}' | head -1)
    fi

    if [ -n "$GIT_SHA" ] && [ "$GIT_SHA" != "unknown" ]; then
      SHORT_SHA=$(echo "$GIT_SHA" | cut -c1-8)
      COMMIT_URL="''${GITHUB_URL}/commit/''${GIT_SHA}"
      SHA_DISPLAY="''${YELLOW}''${LINK_SYM} ''${SHORT_SHA}''${RESET}"
      SHA_LINK="\033]8;;''${COMMIT_URL}\033\\\\''${SHA_DISPLAY}\033]8;;\033\\\\"
    else
      SHORT_SHA="unknown"
      SHA_LINK="''${YELLOW}''${SHORT_SHA}''${RESET}"
    fi

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
        AGE_STR="''${days}d ''${hours}h ''${minutes}m"
      elif [ $hours -gt 0 ]; then
        AGE_STR="''${hours}h ''${minutes}m"
      else
        AGE_STR="''${minutes}m"
      fi
    fi

    UPTIME_STR="unknown"
    if command -v uptime &>/dev/null; then
      UPTIME_RAW=$(uptime)
      if echo "$UPTIME_RAW" | grep -q "up.*days\|up.*day"; then
        UPTIME_STR=$(echo "$UPTIME_RAW" | sed 's/.*up *\([^,]*days\?[^,]*\),.*/\1/' | sed 's/.*up *\([0-9]* days\?\).*/\1/')
      elif echo "$UPTIME_RAW" | grep -q ",.*load"; then
        UPTIME_STR=$(echo "$UPTIME_RAW" | sed 's/.*up *\([^,]*\),.*/\1/')
      else
        UPTIME_STR=$(echo "$UPTIME_RAW" | sed 's/.*up *//; s/,.*//')
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
      if ${pkgs.curl}/bin/curl -sL "https://picsum.photos/200/200" -o "$IMAGE_FILE.tmp" 2>/dev/null; then
        mv "$IMAGE_FILE.tmp" "$IMAGE_FILE"
        date +%Y%m%d > "$STAMP_FILE"
      else
        # If fetch fails, keep old image or continue without image
        rm -f "$IMAGE_FILE.tmp"
      fi
    fi

    WIDTH=50
    LINE=$(printf '%*s' $WIDTH ' ' | tr ' ' '-')

    printf "\n"

    # Display image if available and viu exists
    if [ -f "$IMAGE_FILE" ] && command -v viu &>/dev/null; then
      printf "  "
      viu -w 12 "$IMAGE_FILE" 2>/dev/null || true
      printf "\n"
    fi

    printf "  %b%b  %s  %bNix Configuration%b\n" "''${CYAN}" "''${BOLD}" "''${NIX_SYM}" "''${CYAN}" "''${RESET}"
    printf "  %b%s%b\n" "''${DIM}" "$LINE" "''${RESET}"
    printf "\n"

    ${hostnameLine}
    ${systemLine}
    ${gitCommitLine}

    if [ "$AGE_STR" != "unknown" ]; then
      if [ $AGE_SECONDS -lt 3600 ]; then
        AGE_COLOR="''${GREEN}"
      elif [ $AGE_SECONDS -lt 86400 ]; then
        AGE_COLOR="''${YELLOW}"
      else
        AGE_COLOR="''${ORANGE}"
      fi
      printf "  %b%b%b  %bAge:%b      %b%s%b %bsince last switch%b\n" "''${BLUE}" "''${CLOCK_SYM}" "''${RESET}" "''${BOLD}" "''${RESET}" "''${AGE_COLOR}" "$AGE_STR" "''${RESET}" "''${DIM}" "''${RESET}"
    fi

    printf "  %b%b%b  %bUptime:%b   %b%s%b\n" "''${GREEN}" "''${UPTIME_SYM}" "''${RESET}" "''${BOLD}" "''${RESET}" "''${CYAN}" "$UPTIME_STR" "''${RESET}"

    ${extraMessageBlock}

    printf "\n"
  '';

  motdScript = pkgs.writeShellScriptBin "motd" motdScriptText;
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [motdScript pkgs.viu pkgs.curl];

    programs.zsh = {
      interactiveShellInit = ''
        if [ -z "''${INSIDE_EMACS}" ] && [ "''${TERM}" != "dumb" ] && [ -z "''${VSCODE_RESOLVING_ENVIRONMENT}" ]; then
          if command -v motd &>/dev/null; then
            motd 2>/dev/null
          fi
        fi
      '';
    };

    programs.bash = {
      interactiveShellInit = ''
        if [ -z "''${INSIDE_EMACS}" ] && [ "''${TERM}" != "dumb" ] && [ -z "''${VSCODE_RESOLVING_ENVIRONMENT}" ]; then
          if command -v motd &>/dev/null; then
            motd 2>/dev/null
          fi
        fi
      '';
    };
  };
}
