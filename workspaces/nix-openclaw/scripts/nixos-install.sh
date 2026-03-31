#!/usr/bin/env bash
# NixOS Flake Installer
# Interactive installer for deploying NixOS systems from GitHub flake
# Supports both Live USB (fresh install) and existing NixOS systems
#
# Usage:
#   Local: sudo ./scripts/nixos-install.sh
#   Remote: curl -fsSL https://raw.githubusercontent.com/funkymonkeymonk/nix/main/scripts/nixos-install.sh | sudo bash
#   Remote with branch: curl -fsSL ... | sudo bash -s -- --branch ez-install

set -exuo pipefail

# Error handler
trap 'log_error "Script exited with error at line $LINENO"; cleanup' ERR

# Cleanup function for temp files
cleanup() {
  if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
    log_info "Cleaning up temp directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
  fi
}

# Default configuration
FLAKE_URL="github:funkymonkeymonk/nix"
GITHUB_BRANCH="main"
GITHUB_RAW_URL="https://raw.githubusercontent.com/funkymonkeymonk/nix/main"

# Debug mode - can be enabled with --debug
DEBUG=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch|-b)
      GITHUB_BRANCH="$2"
      shift 2
      ;;
    --debug|-d)
      DEBUG=true
      shift
      ;;
    --help|-h)
      echo "NixOS Flake Installer"
      echo ""
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -b, --branch BRANCH    Use specific branch (default: main)"
      echo "  -d, --debug           Enable debug mode (set -x)"
      echo "  -h, --help            Show this help message"
      echo ""
      echo "Examples:"
      echo "  Local: sudo ./scripts/nixos-install.sh"
      echo "  Remote: curl -fsSL .../main/scripts/nixos-install.sh | sudo bash"
      echo "  Remote with branch: curl -fsSL ... | sudo bash -s -- --branch ez-install"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Disable debug if not explicitly enabled
if [[ "$DEBUG" != true ]]; then
  set +x
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Read input function - uses /dev/tty when running remotely (piped via curl)
read_input() {
  local prompt="$1"
  local var="$2"

  if [[ "$REMOTE_MODE" == true ]]; then
    # When piping via curl, read from terminal directly
    read -rp "$prompt" "$var" < /dev/tty
  else
    # Normal local execution
    read -rp "$prompt" "$var"
  fi
}

# Detect if being run remotely (piped via curl/wget)
REMOTE_MODE=false
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -z "$SCRIPT_SOURCE" ]] || [[ ! -f "$SCRIPT_SOURCE" ]]; then
  REMOTE_MODE=true
fi

# Update URL based on branch for downloading files
# Note: FLAKE_URL always uses main branch for the actual system configuration
GITHUB_RAW_URL="https://raw.githubusercontent.com/funkymonkeymonk/nix/${GITHUB_BRANCH}"

if [[ "$REMOTE_MODE" == true ]]; then
  # Running remotely - clone repo to temp location
  TEMP_DIR="/tmp/nix-flake-installer-$$"
  # Define log_info for early use
  log_info_early() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
  log_info_early "Running in remote mode - downloading files from branch: $GITHUB_BRANCH"
  mkdir -p "$TEMP_DIR"
  cd "$TEMP_DIR"

  # Download necessary files
  curl -fsSL "$GITHUB_RAW_URL/scripts/nixos-install.sh" -o nixos-install.sh
  curl -fsSL "$GITHUB_RAW_URL/scripts/lib/bootstrap-config.nix" -o bootstrap-config.nix

  # Download SSH keys
  mkdir -p keys
  # GitHub doesn't allow directory listing, so we download known keys
  curl -fsSL "$GITHUB_RAW_URL/keys/monkey@MegamanX.pub" -o keys/monkey@MegamanX.pub 2>/dev/null || true

  SCRIPT_DIR="$TEMP_DIR"
  REPO_DIR="$TEMP_DIR"
  KEYS_DIR="$TEMP_DIR/keys"
else
  # Running locally
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  KEYS_DIR="$REPO_DIR/keys"
fi

# Check if running as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    log_info "On Live USB: sudo $(basename "$0")"
    exit 1
  fi
}

# Detect installation mode
detect_mode() {
  log_info "Detecting installation mode..."
  log_info "  Checking /home/nixos: $([[ -d /home/nixos ]] && echo 'exists' || echo 'not found')"
  log_info "  Checking /nix/store: $([[ -d /nix/store ]] && echo 'exists' || echo 'not found')"
  log_info "  Checking /etc/NIXOS: $([[ -f /etc/NIXOS ]] && echo 'exists' || echo 'not found')"
  log_info "  Checking /home/monkey: $([[ -d /home/monkey ]] && echo 'exists' || echo 'not found')"
  log_info "  Checking /home/wweaver: $([[ -d /home/wweaver ]] && echo 'exists' || echo 'not found')"

  if [[ -d /home/nixos ]] && [[ -d /nix/store ]]; then
    # Check if we're on NixOS installer
    if [[ -f /etc/NIXOS ]] && [[ ! -d /home/monkey ]] && [[ ! -d /home/wweaver ]]; then
      log_info "  -> Detected: liveusb mode"
      echo "liveusb"
      return
    fi
  fi

  if [[ -f /etc/NIXOS ]] && [[ -d /home ]]; then
    # Check if there are existing user home directories
    local user_count=$(find /home -maxdepth 1 -type d | wc -l)
    log_info "  Home directories found: $user_count"
    if [[ $user_count -gt 1 ]]; then
      log_info "  -> Detected: existing mode"
      echo "existing"
      return
    fi
  fi

  log_info "  -> Detected: unknown mode"
  echo "unknown"
}

# Select SSH keys from keys/ directory
select_ssh_keys() {
  log_info "Scanning for SSH keys in $KEYS_DIR..."

  if [[ ! -d "$KEYS_DIR" ]]; then
    log_error "Keys directory not found: $KEYS_DIR"
    exit 1
  fi

  local keys=()
  while IFS= read -r -d '' keyfile; do
    keys+=("$(basename "$keyfile" .pub)")
  done < <(find "$KEYS_DIR" -name "*.pub" -print0 2>/dev/null || true)

  if [[ ${#keys[@]} -eq 0 ]]; then
    log_error "No SSH keys found in $KEYS_DIR"
    log_info "Please add your public keys following the naming convention: username@hostname.pub"
    exit 1
  fi

  echo ""
  echo "Available SSH keys:"
  echo "-------------------"
  local i=1
  for key in "${keys[@]}"; do
    echo "  $i. $key"
    ((i++))
  done
  echo ""

  # For now, select all keys (can be made interactive if needed)
  log_info "Using all available SSH keys for authorized access"

  # Read all key contents
  local authorized_keys=""
  for keyfile in "$KEYS_DIR"/*.pub; do
    if [[ -f "$keyfile" ]]; then
      authorized_keys+="$(cat "$keyfile")"$'\n'
    fi
  done

  echo "$authorized_keys"
}

# Get available users from flake
get_flake_users() {
  log_info "Fetching available users from flake..."

  # Try to get users from the flake
  # This is a simplified approach - in practice you'd parse the flake.nix
  # For now, we'll use hardcoded defaults based on the repo structure
  echo "monkey me@willweaver.dev"
  echo "wweaver wweaver@justworks.com"
}

# Select admin user
select_admin_user() {
  echo ""
  echo "Available admin users:"
  echo "----------------------"
  echo "  1. monkey (me@willweaver.dev)"
  echo "  2. wweaver (wweaver@justworks.com)"
  echo ""

  while true; do
    read_input "Select admin user [1-2]: " choice
    case $choice in
      1)
        echo "monkey:me@willweaver.dev:Will Weaver"
        return
        ;;
      2)
        echo "wweaver:wweaver@justworks.com:Will Weaver"
        return
        ;;
      *)
        log_warn "Invalid selection. Please choose 1 or 2."
        ;;
    esac
  done
}

# Check if target exists in flake
# In remote mode, checks GitHub; in local mode, checks filesystem
check_target_exists() {
  local hostname="$1"

  if [[ "$REMOTE_MODE" == true ]]; then
    # Check GitHub for the target
    local target_url="$GITHUB_RAW_URL/targets/$hostname/default.nix"
    if curl -fsSL "$target_url" -o /dev/null 2>/dev/null; then
      return 0
    else
      return 1
    fi
  else
    # Check local filesystem
    local target_dir="$REPO_DIR/targets/$hostname"
    if [[ -d "$target_dir" ]]; then
      return 0
    else
      return 1
    fi
  fi
}

# Guided disk partitioning
guide_partitioning() {
  echo ""
  log_info "Available disks:"
  lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "disk|loop"
  echo ""

  echo "Manual Partitioning Guide:"
  echo "--------------------------"
  echo "1. Identify your target disk (e.g., /dev/sda, /dev/nvme0n1)"
  echo "2. Create partitions using cfdisk or fdisk:"
  echo "   - EFI System Partition (ESP): ~512MB, type: EFI System"
  echo "   - Root partition: remaining space, type: Linux filesystem"
  echo ""
  echo "Example partition layout:"
  echo "   /dev/sda1 - 512MB - EFI System (boot)"
  echo "   /dev/sda2 - rest  - Linux filesystem (/)"
  echo ""

  read_input "Would you like to open cfdisk now? [Y/n]: " open_cfdisk
  if [[ ! "$open_cfdisk" =~ ^[Nn]$ ]]; then
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL
    echo ""
    read_input "Enter disk device (e.g., /dev/sda): " disk
    cfdisk "$disk"
  fi

  echo ""
  log_info "After partitioning, you'll need to:"
  echo "  1. Format partitions: mkfs.vfat /dev/sda1 && mkfs.ext4 /dev/sda2"
  echo "  2. Mount filesystems"
  echo ""

  read_input "Would you like guidance with formatting? [Y/n]: " do_format
  if [[ ! "$do_format" =~ ^[Nn]$ ]]; then
    echo ""
    lsblk
    echo ""
    read_input "Enter EFI partition (e.g., /dev/sda1): " efi_part
    read_input "Enter root partition (e.g., /dev/sda2): " root_part

    log_info "Formatting $efi_part as vfat..."
    mkfs.vfat -F 32 -n boot "$efi_part"

    log_info "Formatting $root_part as ext4..."
    mkfs.ext4 -L nixos "$root_part"

    log_success "Partitions formatted successfully"

    echo ""
    log_info "Mounting filesystems..."
    mount "$root_part" /mnt
    mkdir -p /mnt/boot
    mount "$efi_part" /mnt/boot

    log_success "Filesystems mounted at /mnt"
  fi
}

# Generate hardware configuration
generate_hardware_config() {
  log_info "Generating hardware-configuration.nix..."

  if [[ ! -d /mnt/etc/nixos ]]; then
    mkdir -p /mnt/etc/nixos
  fi

  nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hardware-configuration.nix

  log_success "Hardware configuration generated"
  log_info "Location: /mnt/etc/nixos/hardware-configuration.nix"
}

# Create bootstrap configuration
create_bootstrap_config() {
  local hostname="$1"
  local admin_user="$2"
  local admin_email="$3"
  local admin_fullname="$4"
  local ssh_keys="$5"

  log_info "Creating bootstrap configuration..."

  local config_file="/mnt/etc/nixos/configuration.nix"

  cat > "$config_file" << 'EOF'
# Bootstrap NixOS configuration for HOSTNAME_PLACEHOLDER
# This minimal configuration gets the system running.
# After installation, create a proper target in the flake repository.
{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.device = lib.mkDefault "/dev/sda";
  boot.loader.grub.useOSProber = true;

  # Networking
  networking.hostName = "HOSTNAME_PLACEHOLDER";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # Time zone
  time.timeZone = "America/New_York";

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Essential packages
  environment.systemPackages = with pkgs; [
    git vim wget curl htop tmux
  ];

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 ];

  # Admin user
  users.users.ADMIN_USER_PLACEHOLDER = {
    isNormalUser = true;
    description = "FULLNAME_PLACEHOLDER";
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
SSH_KEYS_PLACEHOLDER
    ];
  };

  # Guest user
  users.users.guest = {
    isNormalUser = true;
    description = "Guest User";
    extraGroups = [ "networkmanager" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
SSH_KEYS_PLACEHOLDER
    ];
  };

  programs.zsh.enable = true;

  # Auto-upgrade from GitHub
  system.autoUpgrade = {
    enable = true;
    flake = "github:funkymonkeymonk/nix";
    flags = [ "-L" "--refresh" ];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };

  system.stateVersion = "25.05";
}
EOF

  # Replace placeholders
  sed -i "s/HOSTNAME_PLACEHOLDER/$hostname/g" "$config_file"
  sed -i "s/ADMIN_USER_PLACEHOLDER/$admin_user/g" "$config_file"
  sed -i "s/FULLNAME_PLACEHOLDER/$admin_fullname/g" "$config_file"

  # Format SSH keys for Nix
  local formatted_keys=""
  while IFS= read -r key; do
    if [[ -n "$key" ]]; then
      formatted_keys+="      \"$key\""$'\n'
    fi
  done <<< "$ssh_keys"

  # Replace SSH keys placeholder
  sed -i "/SSH_KEYS_PLACEHOLDER/c\\$formatted_keys" "$config_file"
  # Remove the placeholder line if it still exists
  sed -i '/SSH_KEYS_PLACEHOLDER/d' "$config_file"

  log_success "Bootstrap configuration created"
  log_info "Location: $config_file"
}

# Install NixOS (Live USB mode)
install_nixos_fresh() {
  local hostname="$1"
  local admin_user="$2"
  local ssh_keys="$3"

  log_info "Installing NixOS..."

  # Install
  nixos-install --no-root-passwd --root /mnt

  log_success "Installation complete!"
}

# Apply flake to existing NixOS
apply_flake_existing() {
  local hostname="$1"

  log_info "[apply_flake_existing] Starting for hostname: $hostname"
  log_info "[apply_flake_existing] FLAKE_URL: ${FLAKE_URL}"

  log_info "Backing up current configuration..."
  local backup_dir="/etc/nixos/backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"
  cp -r /etc/nixos/*.nix "$backup_dir/" 2>/dev/null || true
  log_info "Backup saved to: $backup_dir"

  log_info "Applying flake configuration..."
  log_info "Command: nixos-rebuild switch --flake ${FLAKE_URL}#${hostname}"

  # Apply the configuration
  nixos-rebuild switch --flake "${FLAKE_URL}#${hostname}"

  log_success "Configuration applied successfully!"
}

# Main installation flow
main() {
  echo "=========================================="
  echo "  NixOS Flake Installer"
  echo "  github:funkymonkeymonk/nix"
  echo "=========================================="
  echo ""

  log_info "Step 1: Checking root..."
  check_root
  log_info "Root check passed"

  log_info "Step 2: Detecting mode..."
  local mode
  mode=$(detect_mode)

  log_info "Detected mode: $mode"
  echo ""

  case $mode in
    liveusb)
      log_info "Running in Live USB mode (fresh installation)"
      ;;
    existing)
      log_info "Running on existing NixOS system"
      ;;
    unknown)
      log_error "Could not detect installation mode"
      log_info "This script should be run from NixOS Live USB or an existing NixOS installation"
      exit 1
      ;;
  esac

  log_info "Step 3: Getting hostname..."
  # Get hostname
  read_input "Enter hostname for this machine: " hostname

  if [[ -z "${hostname:-}" ]]; then
    log_error "Hostname cannot be empty"
    exit 1
  fi
  log_info "Hostname set to: $hostname"

  log_info "Step 4: Checking if target exists..."
  # Check if target exists
  local target_exists=false
  if check_target_exists "$hostname"; then
    target_exists=true
    log_info "Found existing target: targets/$hostname"
  else
    log_warn "Target not found: targets/$hostname"
    log_info "Will use bootstrap configuration"
  fi

  log_info "Step 5: Selecting SSH keys..."
  # Select SSH keys
  local ssh_keys
  ssh_keys=$(select_ssh_keys)

  if [[ -z "$ssh_keys" ]]; then
    log_error "No SSH keys selected"
    exit 1
  fi
  log_info "SSH keys selected"

  log_info "Step 6: Selecting admin user..."
  # Select admin user
  local user_info
  user_info=$(select_admin_user)

  local admin_user=$(echo "$user_info" | cut -d: -f1)
  local admin_email=$(echo "$user_info" | cut -d: -f2)
  local admin_fullname=$(echo "$user_info" | cut -d: -f3)

  log_info "Selected admin user: $admin_user ($admin_email)"

  # Show summary
  echo ""
  echo "Installation Summary:"
  echo "--------------------"
  echo "  Hostname: $hostname"
  echo "  Mode: $mode"
  echo "  Target exists: $target_exists"
  echo "  Admin user: $admin_user"
  echo "  SSH keys: $(echo "$ssh_keys" | wc -l) key(s)"
  echo ""

  read_input "Proceed with installation? [Y/n]: " confirm
  if [[ "${confirm:-}" =~ ^[Nn]$ ]]; then
    log_info "Installation cancelled"
    exit 0
  fi

  log_info "Step 8: Executing based on mode: $mode"
  # Execute based on mode
  if [[ "$mode" == "liveusb" ]]; then
    # Live USB mode
    guide_partitioning
    generate_hardware_config

    if [[ "$target_exists" == true ]]; then
      log_info "Using existing target configuration"
      # Copy hardware config to the target location
      mkdir -p "/mnt/etc/nixos"
      cp "/mnt/etc/nixos/hardware-configuration.nix" "/mnt/etc/nixos/"
      # Install using the flake
      nixos-install --no-root-passwd --root /mnt --flake "${FLAKE_URL}#${hostname}"
    else
      log_info "Creating bootstrap configuration"
      create_bootstrap_config "$hostname" "$admin_user" "$admin_email" "$admin_fullname" "$ssh_keys"
      install_nixos_fresh "$hostname" "$admin_user" "$ssh_keys"
    fi

    echo ""
    log_success "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "-----------"
    echo "1. Reboot: reboot"
    echo "2. SSH into the machine: ssh $admin_user@$hostname"
    echo "3. Also available: ssh guest@$hostname"
    echo ""

    if [[ "$target_exists" == false ]]; then
      echo "IMPORTANT: Bootstrap configuration installed!"
      echo ""
      echo "To create a proper target configuration:"
      echo "1. Copy hardware-configuration.nix from the new system:"
      echo "   scp $admin_user@$hostname:/etc/nixos/hardware-configuration.nix \\"
      echo "       targets/$hostname/"
      echo "2. Create targets/$hostname/default.nix with your custom config"
      echo "3. Add the target to flake.nix"
      echo "4. Commit and push:"
      echo "   git add targets/$hostname"
      echo "   git commit -m 'feat: add $hostname target'"
      echo "   git push"
      echo "5. On the new machine, apply the full configuration:"
      echo "   sudo nixos-rebuild switch --flake ${FLAKE_URL}#$hostname"
      echo ""
    fi

  else
    # Existing system mode
    log_info "Entering existing system mode..."
    apply_flake_existing "$hostname"

    echo ""
    log_success "Configuration applied!"
    echo ""
    echo "The system will auto-upgrade daily at 02:00 from:"
    echo "  ${FLAKE_URL}"
    echo ""
  fi
}

# Run main function
main "$@"
