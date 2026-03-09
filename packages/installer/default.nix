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

  # Guide disk partitioning
  guide_partitioning() {
    echo ""
    log_info "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "disk|loop"
    echo ""

    echo "Manual Partitioning Guide:"
    echo "--------------------------"
    echo "1. Identify your target disk (e.g., /dev/sda, /dev/nvme0n1)"
    echo "2. Create partitions using cfdisk or fdisk:"
    echo "   - EFI System Partition (ESP): ~512MB, type: EFI System (if UEFI)"
    echo "   - Root partition: remaining space, type: Linux filesystem"
    echo ""
    echo "Example partition layout:"
    echo "   /dev/sda1 - 512MB - EFI System (boot)"
    echo "   /dev/sda2 - rest  - Linux filesystem (/)"
    echo ""

    read -rp "Would you like to open cfdisk now? [Y/n]: " open_cfdisk
    if [[ ! "$open_cfdisk" =~ ^[Nn]$ ]]; then
      echo "Available disks:"
      lsblk -d -o NAME,SIZE,MODEL
      echo ""
      read -rp "Enter disk device (e.g., /dev/sda): " disk
      cfdisk "$disk"
    fi

    echo ""
    log_info "After partitioning, you'll need to:"
    echo "  1. Format partitions: mkfs.vfat /dev/sda1 && mkfs.ext4 /dev/sda2"
    echo "  2. Mount filesystems"
    echo ""

    read -rp "Would you like guidance with formatting? [Y/n]: " do_format
    if [[ ! "$do_format" =~ ^[Nn]$ ]]; then
      echo ""
      lsblk
      echo ""
      read -rp "Enter boot partition (e.g., /dev/sda1 or leave blank for BIOS): " boot_part
      read -rp "Enter root partition (e.g., /dev/sda2): " root_part

      if [[ -n "$boot_part" ]]; then
        log_info "Formatting $boot_part as vfat..."
        mkfs.vfat -F 32 -n boot "$boot_part"
      fi

      log_info "Formatting $root_part as ext4..."
      mkfs.ext4 -L nixos "$root_part"

      log_success "Partitions formatted successfully"

      echo ""
      log_info "Mounting filesystems..."
      mount "$root_part" /mnt

      if [[ -n "$boot_part" ]]; then
        mkdir -p /mnt/boot
        mount "$boot_part" /mnt/boot
      fi

      log_success "Filesystems mounted at /mnt"
    fi
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
    log_warn "Target not found - will create bootstrap configuration"
    log_info "You can create a proper target after installation"
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

  # Step 3: Disk setup (only for Live USB)
  if [[ "$MODE" == "liveusb" ]]; then
    echo ""
    log_title "Step 3: Disk Setup"
    echo ""

    read -rp "Do you need to partition/format disks? [Y/n]: " setup_disks
    if [[ ! "$setup_disks" =~ ^[Nn]$ ]]; then
      guide_partitioning
    fi
  fi

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
  echo "  Installation Plan:"
  echo "    1. Install bootstrap configuration"
  if [[ "$MODE" == "liveusb" ]]; then
    echo "    2. Reboot into new system"
    echo "    3. Apply full configuration (hostname: $HOSTNAME)"
  else
    echo "    2. Apply full configuration (hostname: $HOSTNAME)"
  fi
  echo ""

  read -rp "Proceed with installation? [Y/n]: " CONFIRM
  if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    log_info "Installation cancelled"
    exit 0
  fi

  # Install
  echo ""
  if [[ "$MODE" == "liveusb" ]]; then
    # Verify /mnt is mounted
    if ! mountpoint -q /mnt; then
      log_error "/mnt is not mounted!"
      log_info "Please partition, format, and mount your filesystems first"
      exit 1
    fi

    # Stage 1: Install bootstrap configuration
    echo ""
    log_title "Stage 1: Installing Bootstrap Configuration"
    echo ""
    log_info "This installs a minimal system that works on any hardware"

    log_info "Installing NixOS with bootstrap configuration..."
    nixos-install --no-root-passwd --root /mnt --flake "$FLAKE_URL#bootstrap"

    log_success "Bootstrap installation complete!"

    # Stage 2: Instructions for applying full config
    echo ""
    log_title "Stage 2: Apply Full Configuration"
    echo ""
    log_info "After reboot, apply your full configuration:"
    echo ""
    echo "  1. Reboot into the new system:"
    echo "     reboot"
    echo ""
    echo "  2. SSH into the machine (from another computer):"
    echo "     ssh bootstrap@<ip-address>"
    echo "     (password will be prompted on first login, then set SSH keys)"
    echo ""
    echo "  3. Apply the full configuration:"
    if [[ "$TARGET_EXISTS" == "true" ]]; then
      echo "     sudo nixos-rebuild switch --flake $FLAKE_URL#$HOSTNAME"
      echo ""
      log_success "Target '$HOSTNAME' is ready to apply!"
    else
      echo "     # First, copy hardware config and create target:"
      echo "     sudo cp /etc/nixos/hardware-configuration.nix /tmp/"
      echo "     # Add to flake repository, commit, and push"
      echo "     sudo nixos-rebuild switch --flake $FLAKE_URL#$HOSTNAME"
      echo ""
      log_warn "Target '$HOSTNAME' does not exist yet"
      log_info "Steps to create it:"
      log_info "  1. Copy /etc/nixos/hardware-configuration.nix"
      log_info "  2. Create targets/$HOSTNAME/default.nix"
      log_info "  3. Add to flake.nix and push"
    fi
    echo ""
    echo "Alternatively, the bootstrap system will automatically try to apply"
    echo "the configuration matching the hostname on first boot (if network is available)"

  else
    # Existing system mode - apply bootstrap first, then full config
    log_info "Applying bootstrap configuration first..."
    nixos-rebuild switch --flake "$FLAKE_URL#bootstrap"

    log_success "Bootstrap applied!"
    echo ""
    log_info "Now applying full configuration: $FLAKE_URL#$HOSTNAME"
    nixos-rebuild switch --flake "$FLAKE_URL#$HOSTNAME" || {
      log_warn "Full configuration failed - you may need to:"
      log_info "  1. Ensure hardware-configuration.nix exists"
      log_info "  2. Check that target '$HOSTNAME' exists in the flake"
    }

    echo ""
    log_success "Configuration process complete!"
    echo ""
    echo "System will auto-upgrade daily at 02:00 from:"
    echo "  $FLAKE_URL"
  fi

  echo ""
  read -rp "Press Enter to exit..."
''
