{pkgs, ...}:
pkgs.writeScriptBin "nixos-flake-installer" ''
  #!${pkgs.bash}/bin/bash
  set -e

  FLAKE_URL="github:funkymonkeymonk/nix"

  # Colors
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  MAGENTA='\033[0;35m'
  NC='\033[0m'

  log_info() { echo -e "''${BLUE}[INFO]''${NC} $1"; }
  log_success() { echo -e "''${GREEN}[SUCCESS]''${NC} $1"; }
  log_warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }
  log_error() { echo -e "''${RED}[ERROR]''${NC} $1"; }
  log_title() { echo -e "''${MAGENTA}$1''${NC}"; }

  # Check root
  if [[ $EUID -ne 0 ]]; then
    log_error "This installer must be run as root"
    log_info "Run with: sudo nix run github:funkymonkeymonk/nix#installer"
    exit 1
  fi

  # Detect mode
  detect_mode() {
    if [[ -d /home/nixos ]] && [[ -d /nix/store ]] && [[ -f /etc/NIXOS ]]; then
      if [[ ! -d /home/monkey ]] && [[ ! -d /home/wweaver ]]; then
        echo "liveusb"
        return
      fi
    fi

    if [[ -f /etc/NIXOS ]] && [[ -d /home ]]; then
      echo "existing"
      return
    fi

    echo "unknown"
  }

  # Fetch targets from GitHub
  fetch_targets() {
    ${pkgs.curl}/bin/curl -s "https://api.github.com/repos/funkymonkeymonk/nix/git/trees/main?recursive=1" 2>/dev/null | \
      ${pkgs.gnugrep}/bin/grep -o '"path":"targets/[^"]*default.nix"' | \
      ${pkgs.gnused}/bin/sed 's/.*targets\//\n/g' | \
      ${pkgs.gnused}/bin/sed 's/\/default.nix.*//g' | \
      sort -u | \
      ${pkgs.gnugrep}/bin/grep -v '^$' || true
  }

  MODE=$(detect_mode)

  clear
  log_title "========================================"
  log_title "  NixOS Flake Installer"
  log_title "  $FLAKE_URL"
  log_title "========================================"
  echo ""

  log_info "Detected Mode: $MODE"

  if [[ "$MODE" == "unknown" ]]; then
    log_error "Could not detect installation mode"
    log_info "This must be run from NixOS Live USB or an existing NixOS system"
    exit 1
  fi

  echo ""
  read -rp "Press Enter to continue..."

  # Step 1: Hostname
  clear
  log_title "Step 1: Hostname"
  echo ""
  read -rp "Enter hostname for this machine [nixos]: " HOSTNAME
  HOSTNAME=''${HOSTNAME:-nixos}
  log_info "Hostname set to: $HOSTNAME"

  # Check if target exists
  echo ""
  log_info "Checking available targets..."
  TARGETS=$(fetch_targets)
  TARGET_EXISTS=false

  if echo "$TARGETS" | ${pkgs.gnugrep}/bin/grep -qx "$HOSTNAME"; then
    TARGET_EXISTS=true
    log_success "Target 'targets/$HOSTNAME' found in flake"
  else
    log_warn "Target not found - will use bootstrap configuration"
  fi

  # Step 2: Admin User
  echo ""
  log_title "Step 2: Admin User"
  echo ""
  echo "Available admin users:"
  echo "  1. monkey (me@willweaver.dev)"
  echo "  2. wweaver (wweaver@justworks.com)"
  echo ""

  while true; do
    read -rp "Select admin user [1-2]: " CHOICE
    case $CHOICE in
      1) ADMIN_USER="monkey"; ADMIN_EMAIL="me@willweaver.dev"; break ;;
      2) ADMIN_USER="wweaver"; ADMIN_EMAIL="wweaver@justworks.com"; break ;;
      *) log_warn "Invalid selection. Please choose 1 or 2." ;;
    esac
  done

  log_info "Selected admin user: $ADMIN_USER"

  # Review
  echo ""
  log_title "Review Configuration"
  echo ""
  echo "  Hostname:      $HOSTNAME"
  echo "  Admin User:    $ADMIN_USER ($ADMIN_EMAIL)"
  echo "  Target Exists: $TARGET_EXISTS"
  echo "  Mode:          $MODE"
  echo "  Flake:         $FLAKE_URL"
  echo ""

  read -rp "Proceed with installation? [Y/n]: " CONFIRM
  if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    log_info "Installation cancelled"
    exit 0
  fi

  # Install
  echo ""
  if [[ "$MODE" == "liveusb" ]]; then
    log_info "Generating hardware configuration..."
    mkdir -p /mnt/etc/nixos
    nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hardware-configuration.nix
    log_success "Hardware configuration generated"

    echo ""
    log_info "Installing NixOS with flake: $FLAKE_URL#$HOSTNAME"
    nixos-install --no-root-passwd --root /mnt --flake "$FLAKE_URL#$HOSTNAME"

    echo ""
    log_success "Installation Complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Reboot: reboot"
    echo "  2. SSH: ssh $ADMIN_USER@$HOSTNAME"

    if [[ "$TARGET_EXISTS" == "false" ]]; then
      echo ""
      log_warn "Note: Bootstrap configuration installed!"
      log_info "Create a proper target by:"
      log_info "  1. Copy hardware-config:"
      log_info "     scp $ADMIN_USER@$HOSTNAME:/etc/nixos/hardware-configuration.nix targets/$HOSTNAME/"
      log_info "  2. Create targets/$HOSTNAME/default.nix"
      log_info "  3. Add to flake.nix, commit, and push"
    fi
  else
    log_info "Applying flake configuration: $FLAKE_URL#$HOSTNAME"
    nixos-rebuild switch --flake "$FLAKE_URL#$HOSTNAME"

    echo ""
    log_success "Configuration applied!"
    echo ""
    echo "System will auto-upgrade daily from:"
    echo "  $FLAKE_URL"
  fi

  echo ""
  read -rp "Press Enter to exit..."
''
