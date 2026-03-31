{pkgs, ...}:
pkgs.writeScriptBin "nixos-installer-iso" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Configuration
    REMOTE_FLAKE="github:funkymonkeymonk/nix"
    LOCAL_FLAKE="/iso/nix-flake"
    ACTIVE_FLAKE=""
    FLAKE_SOURCE=""

    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
    BOLD='\033[1m'

    log_info() { echo -e "''${BLUE}[INFO]''${NC} $1"; }
    log_success() { echo -e "''${GREEN}[SUCCESS]''${NC} $1"; }
    log_warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }
    log_error() { echo -e "''${RED}[ERROR]''${NC} $1"; }
    log_title() { echo -e "''${MAGENTA}''${BOLD}$1''${NC}"; }
    log_step() { echo -e "''${CYAN}→''${NC} $1"; }

    # Check network connectivity
    check_network() {
      log_step "Checking network connectivity..."
      if ${pkgs.curl}/bin/curl -s --max-time 5 https://github.com > /dev/null 2>&1; then
        return 0
      else
        return 1
      fi
    }

    # Determine which flake to use
    select_flake() {
      log_title "═══════════════════════════════════════════════════════════"
      log_title "     NixOS Flake Installer"
      log_title "═══════════════════════════════════════════════════════════"
      echo ""

      if check_network; then
        log_success "Network connection available"
        log_info "Using remote flake: $REMOTE_FLAKE"
        ACTIVE_FLAKE="$REMOTE_FLAKE"
        FLAKE_SOURCE="remote"
      else
        log_warn "No network connection detected"
        if [ -d "$LOCAL_FLAKE" ]; then
          log_info "Using local flake from ISO"
          ACTIVE_FLAKE="$LOCAL_FLAKE"
          FLAKE_SOURCE="local"
          log_warn "Local flake may be older than remote"
        else
          log_error "No local flake found in ISO"
          log_info "The installer requires either:"
          log_info "  1. Network connectivity to GitHub, OR"
          log_info "  2. A local flake bundled in the ISO"
          echo ""
          read -p "Press Enter to open a shell for network troubleshooting..."
          ${pkgs.bash}/bin/bash
          exit 1
        fi
      fi
      echo ""
    }

    # Fetch available targets from flake
    fetch_targets() {
      log_step "Fetching available targets..."

      local targets=""
      if [ "$FLAKE_SOURCE" = "remote" ]; then
        # Try to get from GitHub API
        targets=$(${pkgs.curl}/bin/curl -s "https://api.github.com/repos/funkymonkeymonk/nix/git/trees/main?recursive=1" 2>/dev/null | \
          ${pkgs.gnugrep}/bin/grep -o '"path":"targets/[^"]*default.nix"' | \
          ${pkgs.gnused}/bin/sed 's/.*targets\///g' | \
          ${pkgs.gnused}/bin/sed 's/\/default.nix.*//g' | \
          ${pkgs.gnugrep}/bin/grep -v "^$" | \
          sort -u || true)
      else
        # Get from local filesystem
        if [ -d "$LOCAL_FLAKE/targets" ]; then
          targets=$(find "$LOCAL_FLAKE/targets" -name "default.nix" -exec dirname {} \; | \
            ${pkgs.gnused}/bin/sed "s|$LOCAL_FLAKE/targets/||g" | \
            sort -u || true)
        fi
      fi

      echo "$targets"
    }

    # Display welcome banner with gum
    show_welcome() {
      ${pkgs.gum}/bin/gum style \
        --border double \
        --align center \
        --width 70 \
        --margin "1 2" \
        --padding "1 2" \
        "$(${pkgs.gum}/bin/gum style --foreground 212 --bold "🐧 NixOS Flake Installer")" \
        "" \
        "$(${pkgs.gum}/bin/gum style --foreground 240 "Install NixOS from your flake configuration")" \
        "" \
        "$(${pkgs.gum}/bin/gum style --foreground 242 "Flake: $ACTIVE_FLAKE")" \
        "$(${pkgs.gum}/bin/gum style --foreground 242 "Source: $FLAKE_SOURCE")"
    }

    # Step 1: Get hostname
    get_hostname() {
      echo ""
      ${pkgs.gum}/bin/gum style --foreground 99 --bold "Step 1: Hostname"
      echo ""

      local suggested="nixos"
      HOSTNAME=$(${pkgs.gum}/bin/gum input \
        --placeholder "$suggested" \
        --prompt "Enter hostname for this machine: ")

      HOSTNAME="''${HOSTNAME:-$suggested}"

      # Validate hostname
      if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
        ${pkgs.gum}/bin/gum style --foreground 196 "❌ Invalid hostname. Use only letters, numbers, and hyphens."
        get_hostname
        return
      fi

      log_success "Hostname: $HOSTNAME"
    }

    # Step 2: Select target type
    select_target() {
      echo ""
      ${pkgs.gum}/bin/gum style --foreground 99 --bold "Step 2: Configuration Target"
      echo ""

      # Fetch available targets
      local targets
      targets=$(fetch_targets)

      # Check if hostname matches an existing target
      TARGET_EXISTS=false
      if echo "$targets" | ${pkgs.gum}/bin/grep -qx "$HOSTNAME"; then
        TARGET_EXISTS=true
        ${pkgs.gum}/bin/gum style --foreground 82 "✓ Found matching target: $HOSTNAME"

        if ${pkgs.gum}/bin/gum confirm "Use full configuration for '$HOSTNAME'?" --default=true; then
          TARGET="$HOSTNAME"
          return
        fi
      fi

      # Show available targets
      if [ -n "$targets" ]; then
        ${pkgs.gum}/bin/gum style --foreground 242 "Available targets:"
        echo "$targets" | while read -r target; do
          ${pkgs.gum}/bin/gum style --foreground 242 "  • $target"
        done
        echo ""
      fi

      # Select installation type
      ${pkgs.gum}/bin/gum style --foreground 242 "Select installation type:"
      local install_type
      install_type=$(${pkgs.gum}/bin/gum choose \
        --header "Choose a configuration" \
        "type-desktop    - Desktop/workstation (ext4)" \
        "type-server     - Headless server (ext4)" \
        "bootstrap       - Minimal bootstrap config")

      TARGET=$(echo "$install_type" | ${pkgs.gawk}/bin/awk '{print $1}')
      log_success "Selected: $TARGET"
    }

    # Step 3: Disk selection
    select_disk() {
      echo ""
      ${pkgs.gum}/bin/gum style --foreground 99 --bold "Step 3: Disk Selection"
      echo ""

      ${pkgs.gum}/bin/gum style --foreground 242 "Scanning available disks..."

      # Get disk info
      local disk_info
      disk_info=$(${pkgs.util-linux}/bin/lsblk -d -o NAME,SIZE,MODEL,TYPE,ROTA -n -p 2>/dev/null | \
        ${pkgs.gnugrep}/bin/grep -E 'disk|loop' || true)

      if [ -z "$disk_info" ]; then
        ${pkgs.gum}/bin/gum style --foreground 196 "❌ No disks found!"
        exit 1
      fi

      # Format options
      local options=()
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local device size model type rota
        device=$(echo "$line" | ${pkgs.gawk}/bin/awk '{print $1}')
        size=$(echo "$line" | ${pkgs.gawk}/bin/awk '{print $2}')
        model=$(echo "$line" | ${pkgs.gawk}/bin/awk '{print $3}')
        type=$(echo "$line" | ${pkgs.gawk}/bin/awk '{print $4}')
        rota=$(echo "$line" | ${pkgs.gawk}/bin/awk '{print $5}')

        local media_type="SSD"
        [ "$rota" = "1" ] && media_type="HDD"
        [ "$type" = "loop" ] && media_type="Loop"

        options+=("$(printf "%-15s %-8s %-6s %s" "$device" "$size" "$media_type" "$model")")
      done <<< "$disk_info"

      if [ ''${#options[@]} -eq 0 ]; then
        ${pkgs.gum}/bin/gum style --foreground 196 "❌ No suitable disks found"
        exit 1
      fi

      # Show header
      printf "%-15s %-8s %-6s %s\n" "DEVICE" "SIZE" "TYPE" "MODEL"
      echo "─────────────────────────────────────────────────────────"

      # Select disk
      DISK=$(${pkgs.gum}/bin/gum choose \
        --header "" \
        "''${options[@]}" | ${pkgs.gawk}/bin/awk '{print $1}')

      if [ -z "$DISK" ]; then
        ${pkgs.gum}/bin/gum style --foreground 196 "❌ No disk selected"
        exit 1
      fi

      # Warning
      echo ""
      ${pkgs.gum}/bin/gum style --foreground 196 --bold "⚠️  WARNING: All data on $DISK will be DESTROYED!"

      if ! ${pkgs.gum}/bin/gum confirm "Are you sure you want to use $DISK?"; then
        select_disk
        return
      fi

      log_success "Selected disk: $DISK"
    }

    # Step 4: Review and confirm
    confirm_install() {
      echo ""
      ${pkgs.gum}/bin/gum style --foreground 99 --bold "Step 4: Review Configuration"
      echo ""

      local target_desc=""
      if [ "$TARGET_EXISTS" = "true" ]; then
        target_desc="Full configuration ($TARGET)"
      else
        case "$TARGET" in
          type-desktop) target_desc="Desktop type (cattle)" ;;
          type-server) target_desc="Server type (cattle)" ;;
          bootstrap) target_desc="Bootstrap (minimal)" ;;
          *) target_desc="$TARGET" ;;
        esac
      fi

      ${pkgs.gum}/bin/gum style \
        --border normal \
        --padding "1 2" \
        "$(${pkgs.gum}/bin/gum style --bold "Installation Summary:")" \
        "" \
        "$(${pkgs.gum}/bin/gum style --foreground 242 "Hostname: ")$(${pkgs.gum}/bin/gum style --foreground 255 "$HOSTNAME")" \
        "$(${pkgs.gum}/bin/gum style --foreground 242 "Target:   ")$(${pkgs.gum}/bin/gum style --foreground 255 "$target_desc")" \
        "$(${pkgs.gum}/bin/gum style --foreground 242 "Disk:     ")$(${pkgs.gum}/bin/gum style --foreground 255 "$DISK")" \
        "$(${pkgs.gum}/bin/gum style --foreground 242 "Flake:    ")$(${pkgs.gum}/bin/gum style --foreground 255 "$ACTIVE_FLAKE")" \
        "$(${pkgs.gum}/bin/gum style --foreground 242 "Format:   ")$(${pkgs.gum}/bin/gum style --foreground 255 "ext4 with disko")"

      echo ""
      ${pkgs.gum}/bin/gum style --foreground 196 --bold "⚠️  This will DESTROY all data on $DISK"
      echo ""

      if ! ${pkgs.gum}/bin/gum confirm "Proceed with installation?"; then
        ${pkgs.gum}/bin/gum style --foreground 214 "Installation cancelled"
        exit 0
      fi
    }

    # Generate SSH host keys
    generate_ssh_keys() {
      local temp_dir=$(mktemp -d)
      mkdir -p "$temp_dir/etc/ssh"

      ${pkgs.gum}/bin/gum spin --spinner dot --title "Generating SSH host keys..." -- \
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f "$temp_dir/etc/ssh/ssh_host_ed25519_key" -N "" -C "root@$HOSTNAME"

      ${pkgs.gum}/bin/gum spin --spinner dot --title "Generating RSA host keys..." -- \
        ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f "$temp_dir/etc/ssh/ssh_host_rsa_key" -N "" -C "root@$HOSTNAME"

      echo "$temp_dir"
    }

    # Perform the installation
    perform_installation() {
      echo ""
      ${pkgs.gum}/bin/gum style --foreground 99 --bold "Installing NixOS..."
      echo ""

      # Generate SSH keys
      local temp_dir
      temp_dir=$(generate_ssh_keys)

      # Create hardware config override
      local hw_config="$temp_dir/hardware.nix"
      cat > "$hw_config" <<-EOF
    {
      # Hardware configuration for $HOSTNAME
      disko.devices.disk.main.device = "$DISK";
      networking.hostName = "$HOSTNAME";
    }
    EOF

      # Build nixos-anywhere command
      local na_args=(
        "--flake" "$ACTIVE_FLAKE#$TARGET"
        "--generate-hardware-config" "nixos-facter" "$temp_dir/facter.json"
        "--extra-files" "$temp_dir"
        "--disko-mode" "destroy"
      )

      # Show what we're doing
      ${pkgs.gum}/bin/gum style --foreground 242 "Running: nixos-anywhere --flake $ACTIVE_FLAKE#$TARGET --disko-mode destroy"
      echo ""

      # Run nixos-anywhere (must be installed or use nix run)
      if ! command -v nixos-anywhere &> /dev/null; then
        log_info "Installing nixos-anywhere..."
        nix profile install github:nix-community/nixos-anywhere
      fi

      # Execute installation
      if nixos-anywhere "''${na_args[@]}"; then
        echo ""
        show_success
      else
        echo ""
        ${pkgs.gum}/bin/gum style --foreground 196 --bold "❌ Installation failed"
        log_error "Check the output above for errors"
        exit 1
      fi

      # Cleanup
      rm -rf "$temp_dir"
    }

    # Success message
    show_success() {
      ${pkgs.gum}/bin/gum style \
        --border double \
        --align center \
        --width 60 \
        --margin "1 2" \
        --padding "2 2" \
        "$(${pkgs.gum}/bin/gum style --foreground 82 --bold "✓ Installation Complete!")" \
        "" \
        "$(${pkgs.gum}/bin/gum style --foreground 255 "Hostname: $HOSTNAME")" \
        "$(${pkgs.gum}/bin/gum style --foreground 255 "Target: $TARGET")" \
        "" \
        "$(${pkgs.gum}/bin/gum style --foreground 242 "Remove USB and reboot")" \
        "$(${pkgs.gum}/bin/gum style "The system will auto-update from your flake")"

      # Show SSH fingerprints
      echo ""
      ${pkgs.gum}/bin/gum style --foreground 242 "SSH host key fingerprints will be shown on first boot"
    }

    # Alternative: Use disko + nixos-install directly (no SSH)
    perform_local_install() {
      echo ""
      ${pkgs.gum}/bin/gum style --foreground 99 --bold "Installing NixOS (local mode)..."
      echo ""

      # Run disko to partition and format
      log_step "Partitioning disk with disko..."

      # Get the disko config from the flake
      # Always create a wrapper config that sets the device
      cat > /tmp/disko-device.nix <<-DISKOEOF
  {
    disko.devices.disk.main.device = "$DISK";
  }
  DISKOEOF

      local disko_config
      local disko_configs
      if [ "$TARGET" = "bootstrap" ]; then
        # Bootstrap uses simple partitioning
        disko_config="$LOCAL_FLAKE/targets/bootstrap/disk-config.nix"
        if [ ! -f "$disko_config" ]; then
          # Create minimal disko config inline
          cat > /tmp/disko-config.nix <<-'DISKOEOF'
  {
    disko.devices = {
      disk.main = {
        type = "disk";
        device = "DISK_PLACEHOLDER";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  }
  DISKOEOF
          sed -i "s|DISK_PLACEHOLDER|$DISK|g" /tmp/disko-config.nix
          disko_config="/tmp/disko-config.nix"
        fi
      else
        # Use the target's disko config
        disko_config="$LOCAL_FLAKE/disk-configs/single-disk-ext4.nix"
        if [ ! -f "$disko_config" ]; then
          log_error "Disk config not found: $disko_config"
          exit 1
        fi
      fi

      # Build disko command - wrapper first to override device
      disko_configs="/tmp/disko-device.nix $disko_config"

      # Run disko
      log_step "Partitioning disk with disko..."
      log_info "This will DESTROY all data on $DISK"
      echo ""
      sudo ${pkgs.disko}/bin/disko --mode destroy,format,mount $disko_configs 2>&1 | tee /tmp/disko.log
      if [ $? -ne 0 ]; then
        log_error "Disko failed! Check /tmp/disko.log for details"
        exit 1
      fi

      if [ -z "$disko_config" ] || [ ! -f "$disko_config" ]; then
        log_warn "No disko config found, manual partitioning required"
        echo "Opening cfdisk for manual partitioning..."
        sudo ${pkgs.util-linux}/bin/cfdisk "$DISK"

        # Ask for partition info
        ${pkgs.gum}/bin/gum style --foreground 242 "Enter partition information:"
        ROOT_PART=$(${pkgs.gum}/bin/gum input --prompt "Root partition (e.g., /dev/sda1): ")
        sudo mkfs.ext4 -L nixos "$ROOT_PART"
        sudo mount "$ROOT_PART" /mnt
      fi

      # Generate hardware config
      log_step "Generating hardware configuration..."
      sudo ${pkgs.nixos-install-tools}/bin/nixos-generate-config --root /mnt

      # Install NixOS
      log_step "Installing NixOS..."
      log_info "This may take 15-30 minutes depending on your connection"
      echo ""

      if sudo ${pkgs.nixos-install-tools}/bin/nixos-install --no-root-passwd --root /mnt --flake "$ACTIVE_FLAKE#$TARGET"; then
        echo ""
        show_success

        # Copy hardware config to somewhere accessible
        if [ "$FLAKE_SOURCE" = "local" ]; then
          sudo mkdir -p /mnt/root/hardware-config
          sudo cp /mnt/etc/nixos/hardware-configuration.nix /mnt/root/hardware-config/
          ${pkgs.gum}/bin/gum style --foreground 242 "Hardware config saved to: /root/hardware-config/"
        fi
      else
        echo ""
        ${pkgs.gum}/bin/gum style --foreground 196 --bold "❌ Installation failed"
        exit 1
      fi
    }

    # Main
    main() {
      # Must be root
      if [ $EUID -ne 0 ]; then
        log_error "This installer must be run as root"
        exit 1
      fi

      # Select flake (remote preferred, local fallback)
      select_flake

      # Show welcome
      show_welcome

      # Get configuration
      get_hostname
      select_target
      select_disk
      confirm_install

      # Install
      perform_local_install
    }

    # Run
    main "$@"
''
