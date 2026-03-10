#!/usr/bin/env bash
# install-machine.sh - Interactive TUI NixOS installer using gum
# Usage: ./install-machine.sh [--debug]
#
# A debug log is automatically created at: ~/.local/share/nixos-installer/logs/nixos-install_YYYYMMDD_HHMMSS.log

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR=$(mktemp -d)
DEBUG_MODE=false

# Create persistent log directory and file with timestamp
LOG_DIR="${HOME}/.local/share/nixos-installer/logs"
mkdir -p "$LOG_DIR"
LOG_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/nixos-install_${LOG_TIMESTAMP}.log"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # In debug mode, also print to stderr
    if [[ "$DEBUG_MODE" == true ]]; then
        echo "[$level] $message" >&2
    fi
}

log_debug() { log "DEBUG" "$@"; }
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# Cleanup on exit
cleanup() {
    local exit_code=$?
    log_info "Script exiting with code $exit_code"
    
    # Always show log file location
    echo ""
    gum style --foreground 214 --bold "📋 Debug Log Available"
    gum style --foreground 242 "Log file: $LOG_FILE"
    
    if [[ $exit_code -ne 0 ]]; then
        if [[ "$DEBUG_MODE" == false ]]; then
            gum style --foreground 242 "Run with --debug for verbose terminal output"
        fi
    fi
    
    # Clean up temp directory but preserve logs
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Check if gum is available
check_gum() {
    log_info "Checking for gum installation"
    if ! command -v gum &> /dev/null; then
        log_error "gum is not installed"
        echo "Error: gum is not installed"
        echo "Install with: nix profile install nixpkgs#gum"
        exit 1
    fi
    log_info "gum found: $(gum --version 2>/dev/null || echo 'version unknown')"
}

# Welcome screen
show_welcome() {
    clear
    gum style \
        --border double \
        --align center \
        --width 60 \
        --margin "1 2" \
        --padding "1 2" \
        "$(gum style --foreground 212 --bold "🐄 NixOS Cattle Installer")" \
        "" \
        "Interactive installer for NixOS machines"
}

# Analyze SSH error and provide specific guidance
analyze_ssh_error() {
    local error_output="$1"
    local target="$2"

    log_error "SSH connection failed: $error_output"

    echo ""
    gum style --foreground 196 --bold "Error Details:"
    echo "$error_output" | head -10 | while read -r line; do
        gum style --foreground 196 "  $line"
    done
    echo ""

    # Analyze specific error patterns
    if echo "$error_output" | grep -qi "connection refused"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: Connection Refused"
        gum style --foreground 242 "SSH is not running on the target machine."
        echo ""
        gum style --foreground 242 "On the target machine, run:"
        gum style --foreground 255 "  systemctl start sshd"
        gum style --foreground 255 "  systemctl enable sshd"

    elif echo "$error_output" | grep -qi "connection timed out\|no route to host"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: Network/Connection Issue"
        gum style --foreground 242 "Cannot reach the target machine."
        echo ""
        gum style --foreground 242 "Check:"
        gum style --foreground 242 "  • Is the IP address correct?"
        gum style --foreground 242 "  • Is the target machine powered on?"
        gum style --foreground 242 "  • Are both machines on the same network?"
        gum style --foreground 242 "  • Is there a firewall blocking port 22?"

    elif echo "$error_output" | grep -qi "permission denied\|authentication failed"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: Authentication Failed"
        gum style --foreground 242 "Username or password is incorrect."
        echo ""
        gum style --foreground 242 "Check:"
        gum style --foreground 242 "  • Is the username correct? (Default: root)"
        gum style --foreground 242 "  • Is the password correct?"
        gum style --foreground 242 "  • Has a password been set on the target?"
        echo ""
        gum style --foreground 242 "On the target machine, set a password:"
        gum style --foreground 255 "  passwd"

    elif echo "$error_output" | grep -qi "could not resolve hostname\|name or service not known"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: DNS Resolution Failed"
        gum style --foreground 242 "Cannot resolve the hostname."
        echo ""
        gum style --foreground 242 "Try using the IP address instead of hostname."
        gum style --foreground 242 "On target, check IP with: ip addr show"

    elif echo "$error_output" | grep -qi "sshpass: command not found"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: Missing sshpass"
        gum style --foreground 242 "sshpass is not installed."
        echo ""
        gum style --foreground 242 "Install with: nix profile install nixpkgs#sshpass"

    else
        gum style --foreground 214 --bold "🔍 Diagnosis: Unknown Error"
        gum style --foreground 242 "An unexpected error occurred during SSH connection."
        echo ""
        gum style --foreground 242 "General troubleshooting:"
        gum style --foreground 242 "  • Target must be booted from NixOS USB"
        gum style --foreground 242 "  • SSH service must be running"
        gum style --foreground 242 "  • Password must be set"
    fi
}

# Step 1: SSH Connection
get_ssh_connection() {
    log_info "Starting Step 1: SSH Connection"
    gum style --foreground 99 --bold "Step 1: Target Machine Connection"
    echo ""

    # Get target host
    local target_host
    target_host=$(gum input \
        --placeholder "192.168.1.100" \
        --prompt "Target IP or hostname: ")

    if [[ -z "$target_host" ]]; then
        log_error "No target host provided"
        gum style --foreground 196 "❌ Target host is required"
        exit 1
    fi
    log_info "Target host: $target_host"

    # Get username (default: root)
    local username="root"
    gum style --foreground 242 "Default SSH username: $(gum style --bold "root")"
    if ! gum confirm "Use 'root' as username?" --default=true; then
        username=$(gum input \
            --placeholder "Enter username..." \
            --prompt "SSH username: ")
        if [[ -z "$username" ]]; then
            username="root"
        fi
        # Warn about sudo requirements for non-root users
        if [[ "$username" != "root" ]]; then
            echo ""
            gum style --foreground 214 "⚠️  Non-root user selected"
            gum style --foreground 242 "You will need to enter your sudo password during installation."
            gum style --foreground 242 "The prompt will appear in the terminal."
            echo ""
        fi
    fi

    TARGET="${username}@${target_host}"
    log_info "Target: $TARGET"

    # Get SSH password
    echo ""
    gum style --foreground 242 "Enter SSH password for ${TARGET}"
    SSH_PASSWORD=$(gum input --password --prompt "Password: ")

    if [[ -z "$SSH_PASSWORD" ]]; then
        log_error "No password provided"
        gum style --foreground 196 "❌ Password is required"
        exit 1
    fi
    log_info "Password received (length: ${#SSH_PASSWORD})"

    # Test SSH connection with password
    gum style --foreground 242 "Testing SSH connection to ${TARGET}..."
    log_info "Testing SSH connection to $TARGET"

    # Capture error output for analysis
    local ssh_output
    local ssh_exit_code=0
    ssh_output=$(sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$TARGET" "echo 'SSH_OK'" 2>&1) || ssh_exit_code=$?

    log_debug "SSH exit code: $ssh_exit_code"
    log_debug "SSH output: $ssh_output"

    if [[ "$ssh_output" == *"SSH_OK"* ]]; then
        log_info "SSH connection successful"
        gum style --foreground 82 "✓ SSH connection successful"
    else
        log_error "SSH connection failed with exit code $ssh_exit_code"
        gum style --foreground 196 "❌ SSH connection failed"
        analyze_ssh_error "$ssh_output" "$TARGET"
        echo ""

        if gum confirm "Would you like to retry?"; then
            get_ssh_connection
        else
            exit 1
        fi
    fi
}

# Step 2: Machine Type Selection
select_machine_type() {
    log_info "Starting Step 2: Machine Type Selection"
    echo ""
    gum style --foreground 99 --bold "Step 2: Machine Type"
    echo ""

    TYPE=$(gum choose \
        --header "Select the type of machine to install:" \
        "desktop    - Gaming/workstation with graphics support" \
        "server     - Headless server" \
        | cut -d' ' -f1)

    log_info "Selected machine type: $TYPE"
    gum style --foreground 82 "✓ Selected: $TYPE"
}

# Step 3: Hostname Generation and Confirmation
get_hostname() {
    log_info "Starting Step 3: Hostname Generation"
    echo ""
    gum style --foreground 99 --bold "Step 3: Hostname"
    echo ""

    # Auto-generate hostname based on existing machines in flake.nix
    local existing_hosts
    existing_hosts=$(grep -oE '"[a-zA-Z0-9_-]+"[[:space:]]*=' "$FLAKE_DIR/flake.nix" 2>/dev/null | grep -oE '[a-zA-Z0-9_-]+' | sort -u || true)

    local suggested_name
    if [[ -n "$existing_hosts" ]]; then
        # Generate a new name based on pattern
        local max_num=0
        while IFS= read -r host; do
            if [[ "$host" =~ ^[a-zA-Z]+([0-9]+)$ ]]; then
                local num="${BASH_REMATCH[1]}"
                (( num > max_num )) && max_num=$num
            fi
        done <<< "$existing_hosts"

        # Suggest next in sequence
        local base_name="nixos"
        if [[ "$TYPE" == "desktop" ]]; then
            base_name="desktop"
        elif [[ "$TYPE" == "server" ]]; then
            base_name="server"
        fi
        suggested_name="${base_name}$((max_num + 1))"
    else
        suggested_name="nixos1"
    fi

    log_info "Suggested hostname: $suggested_name"

    # Show existing hosts for context
    if [[ -n "$existing_hosts" ]]; then
        gum style --foreground 242 "Existing machines:"
        echo "$existing_hosts" | head -10 | while read -r host; do
            gum style --foreground 242 "  • $host"
        done
        echo ""
    fi

    # Ask if they want to use the suggested hostname
    gum style --foreground 242 "Suggested hostname: $(gum style --bold "$suggested_name")"
    if gum confirm "Use this hostname?" --default=true; then
        HOSTNAME="$suggested_name"
        log_info "User accepted suggested hostname: $HOSTNAME"
    else
        # Get custom hostname - starts empty so typing replaces nothing
        HOSTNAME=$(gum input \
            --placeholder "Enter hostname..." \
            --prompt "Hostname for new machine: ")
        
        if [[ -z "$HOSTNAME" ]]; then
            gum style --foreground 196 "❌ Hostname is required"
            get_hostname
            return
        fi
        log_info "User entered custom hostname: $HOSTNAME"
    fi

    log_info "Selected hostname: $HOSTNAME"

    # Validate hostname (alphanumeric and hyphens only)
    if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log_warn "Invalid hostname format: $HOSTNAME"
        gum style --foreground 196 "❌ Invalid hostname. Use only letters, numbers, and hyphens."
        get_hostname
        return
    fi

    gum style --foreground 82 "✓ Hostname: $HOSTNAME"
}

# Step 4: Disk Selection (Interactive with physical device info)
select_disk() {
    echo ""
    gum style --foreground 99 --bold "Step 4: Disk Selection"
    echo ""
    
    # Fetch disk information from target
    gum style --foreground 242 "Scanning available disks on target..."

    local disk_info
    if ! disk_info=$(gum spin --spinner dot --title "Scanning disks..." -- \
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$TARGET" "lsblk -d -o NAME,SIZE,MODEL,TYPE,ROTA -n -p 2>/dev/null | grep -E 'disk|loop' || echo 'ERROR'"); then
        gum style --foreground 196 "❌ Failed to scan disks"
        exit 1
    fi
    
    if [[ "$disk_info" == "ERROR" ]] || [[ -z "$disk_info" ]]; then
        gum style --foreground 196 "❌ No disks found or permission denied"
        exit 1
    fi
    
    # Parse and format disk options
    local disk_options=()
    while IFS= read -r line; do
        local device size model type rota
        device=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        model=$(echo "$line" | awk '{print $3}')
        type=$(echo "$line" | awk '{print $4}')
        rota=$(echo "$line" | awk '{print $5}')
        
        local media_type="SSD"
        [[ "$rota" == "1" ]] && media_type="HDD"
        [[ "$type" == "loop" ]] && media_type="Loop"
        
        local option
        option=$(printf "%-15s %-8s %-6s %s" "$device" "$size" "$media_type" "$model")
        disk_options+=("$option")
    done <<< "$disk_info"
    
    if [[ ${#disk_options[@]} -eq 0 ]]; then
        gum style --foreground 196 "❌ No suitable disks found"
        exit 1
    fi
    
    # Show disk selection
    gum style --foreground 242 "Available disks:"
    printf "%-15s %-8s %-6s %s\n" "DEVICE" "SIZE" "TYPE" "MODEL"
    echo "─────────────────────────────────────────────────────────"
    
    DISK=$(gum choose \
        --header "" \
        "${disk_options[@]}" \
        | awk '{print $1}')
    
    if [[ -z "$DISK" ]]; then
        gum style --foreground 196 "❌ No disk selected"
        exit 1
    fi
    
    # Warning about data destruction
    echo ""
    gum style --foreground 196 --bold "⚠️  WARNING: All data on $DISK will be DESTROYED!"
    
    if ! gum confirm "Are you sure you want to use $DISK?"; then
        select_disk
        return
    fi
    
    gum style --foreground 82 "✓ Selected disk: $DISK"
}

# Step 5: Auto-Update Configuration
configure_autoupdate() {
    echo ""
    gum style --foreground 99 --bold "Step 5: Auto-Update Configuration"
    echo ""
    
    gum style --foreground 242 "Automatically update this machine from a remote flake?"
    echo ""
    
    if gum confirm "Enable auto-updates?" --default=true; then
        AUTO_UPDATE=true
        
        # Default repository
        local default_repo="github:funkymonkeymonk/nix"
        
        gum style --foreground 242 "Default flake repository: $(gum style --bold "$default_repo")"
        if gum confirm "Use this repository?" --default=true; then
            FLAKE_REPO="$default_repo"
        else
            FLAKE_REPO=$(gum input \
                --placeholder "Enter repository..." \
                --prompt "Flake repository: ")
            if [[ -z "$FLAKE_REPO" ]]; then
                FLAKE_REPO="$default_repo"
            fi
        fi
        
        # Time selection with gum choose
        echo ""
        gum style --foreground 242 "Select update time (systemd timer):"
        
        local update_time
        update_time=$(gum choose \
            --header "When should the system check for updates?" \
            "04:00  - Early morning (recommended)" \
            "02:00  - Very early morning" \
            "06:00  - Morning" \
            "00:00  - Midnight" \
            | cut -d' ' -f1)
        
        UPDATE_TIME="${update_time:-04:00}"
        
        gum style --foreground 82 "✓ Auto-updates enabled"
        gum style --foreground 242 "  Repository: $FLAKE_REPO"
        gum style --foreground 242 "  Time: $UPDATE_TIME"
    else
        AUTO_UPDATE=false
        FLAKE_REPO=""
        UPDATE_TIME=""
        gum style --foreground 214 "✓ Auto-updates disabled"
    fi
}

# Step 6: Final Confirmation and Installation
confirm_and_install() {
    echo ""
    gum style --foreground 99 --bold "Step 6: Installation Summary"
    echo ""
    
    # Display summary
    gum style \
        --border normal \
        --padding "1 2" \
        "$(gum style --bold "Installation Details:")" \
        "" \
        "$(gum style --foreground 242 "Hostname:    ")$(gum style --foreground 255 "$HOSTNAME")" \
        "$(gum style --foreground 242 "Type:        ")$(gum style --foreground 255 "$TYPE")" \
        "$(gum style --foreground 242 "Target:      ")$(gum style --foreground 255 "$TARGET")" \
        "$(gum style --foreground 242 "Disk:        ")$(gum style --foreground 255 "$DISK")" \
        "$(gum style --foreground 242 "Auto-update: ")$(if [[ "$AUTO_UPDATE" == true ]]; then gum style --foreground 82 "Enabled ($UPDATE_TIME)"; else gum style --foreground 214 "Disabled"; fi)" \
        "$(if [[ "$AUTO_UPDATE" == true ]]; then echo "$(gum style --foreground 242 "Repository:  ")$(gum style --foreground 255 "$FLAKE_REPO")"; fi)"
    
    echo ""
    gum style --foreground 196 --bold "⚠️  This will DESTROY all data on $DISK"
    echo ""
    
    if ! gum confirm "Proceed with installation?"; then
        gum style --foreground 214 "Installation cancelled"
        exit 0
    fi
    
    # Perform installation
    perform_installation
}

# Generate SSH host keys
generate_ssh_keys() {
    mkdir -p "$TEMP_DIR/etc/ssh"
    
    gum spin --spinner dot --title "Generating SSH host keys..." -- \
        ssh-keygen -t ed25519 -f "$TEMP_DIR/etc/ssh/ssh_host_ed25519_key" -N "" -C "root@$HOSTNAME"
    
    gum spin --spinner dot --title "Generating RSA host keys..." -- \
        ssh-keygen -t rsa -b 4096 -f "$TEMP_DIR/etc/ssh/ssh_host_rsa_key" -N "" -C "root@$HOSTNAME"
}

# Build and run installation
perform_installation() {
    log_info "Starting installation"
    echo ""
    gum style --foreground 99 --bold "Installing NixOS..."
    echo ""

    # Generate SSH keys
    log_info "Generating SSH host keys"
    generate_ssh_keys

    # Create host directory for facter.json
    local host_dir="$FLAKE_DIR/hosts/$HOSTNAME"
    mkdir -p "$host_dir"
    log_info "Created host directory: $host_dir"

    # Create hardware config with disko device set
    local hw_config_file="$TEMP_DIR/hardware.nix"
    cat > "$hw_config_file" << EOF
{
  # Hardware configuration generated by cattle installer
  # Hostname: $HOSTNAME
  # Type: $TYPE

  # Disk configuration
  disko.devices.disk.main.device = "$DISK";

  # Network hostname
  networking.hostName = "$HOSTNAME";

$(if [[ "$AUTO_UPDATE" == true ]]; then cat << 'INNER'
  # Auto-update configuration
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = [ "--update-input" "nixpkgs" "--no-write-lock-file" "-L" ];
    dates = "INNER
    echo "    $UPDATE_TIME";
    cat << 'INNER'
    randomizedDelaySec = "45min";
  };
INNER
fi)
}
EOF
    log_info "Hardware config written to $hw_config_file"

    # Build nixos-anywhere command
    # Note: Password is passed via SSHPASS env var, not as argument
    local na_args=(
        "--flake" "$FLAKE_DIR#type-$TYPE"
        "--target-host" "$TARGET"
        "--generate-hardware-config" "nixos-facter" "$host_dir/facter.json"
        "--extra-files" "$TEMP_DIR"
        "--env-password"
        "--disko-mode" "destroy"
    )

    # Add verbose flag in debug mode
    if [[ "$DEBUG_MODE" == true ]]; then
        na_args+=("--debug")
        log_info "Debug mode enabled - adding --debug flag"
    fi

    # Show command (never log password)
    gum style --foreground 242 "Running: nixos-anywhere --flake $FLAKE_DIR#type-$TYPE --target-host $TARGET --env-password ..."
    log_info "nixos-anywhere args: --flake $FLAKE_DIR#type-$TYPE --target-host $TARGET --generate-hardware-config nixos-facter <path> --extra-files <path> --env-password --disko-mode destroy"
    echo ""

    # Export password for nixos-anywhere via SSHPASS env var
    export SSHPASS="$SSH_PASSWORD"

    # Run installation and capture output
    local install_output
    local install_exit_code=0

    # Add marker to log file for installation output
    echo "" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ==========================================" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] NIXOS-ANYWHERE INSTALLATION OUTPUT START" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ==========================================" >> "$LOG_FILE"

    # Always show output to terminal so interactive prompts (sudo/password) are visible
    # Capture to file for logging purposes
    log_info "Running installation (output visible for interactive prompts)"
    set +e
    local output_capture="$TEMP_DIR/nixos-anywhere-output.txt"
    touch "$output_capture"
    
    # Use script command for capturing if available, otherwise tee
    if command -v script &>/dev/null && script -q /dev/null echo test &>/dev/null; then
        # Linux script command - works well for capturing interactive sessions
        script -q -c "nix run github:nix-community/nixos-anywhere -- ${na_args[*]}" "$output_capture"
        install_exit_code=$?
    else
        # Fallback: use tee to capture output while displaying interactively
        # Note: This may not capture password prompts perfectly on all systems
        nix run github:nix-community/nixos-anywhere -- "${na_args[@]}" 2>&1 | tee "$output_capture"
        install_exit_code=${PIPESTATUS[0]}
    fi
    
    # Store output in variable for error analysis and append to log
    install_output=$(cat "$output_capture" 2>/dev/null || true)
    cat "$output_capture" >> "$LOG_FILE" 2>/dev/null || true
    set -e

    # Add marker to log file for end of installation output
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ==========================================" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] NIXOS-ANYWHERE INSTALLATION OUTPUT END (exit code: $install_exit_code)" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ==========================================" >> "$LOG_FILE"

    # Clear password from environment
    unset SSHPASS

    log_info "Installation exit code: $install_exit_code"

    if [[ $install_exit_code -eq 0 ]]; then
        log_info "Installation completed successfully"
        echo ""
        show_success
    else
        log_error "Installation failed with exit code $install_exit_code"
        echo ""
        gum style --foreground 196 --bold "❌ Installation failed"
        echo ""

        # Show last 20 lines of output
        if [[ -n "$install_output" ]]; then
            gum style --foreground 214 --bold "Last 20 lines of output:"
            echo "$install_output" | tail -20 | while read -r line; do
                gum style --foreground 242 "  $line"
            done
            echo ""
        fi

        # Analyze common errors
        analyze_installation_error "$install_output"

        echo ""
        gum style --foreground 242 "Full log: $LOG_FILE"
        gum style --foreground 242 "Run with --debug for verbose output"

        exit 1
    fi
}

# Analyze installation errors
analyze_installation_error() {
    local output="$1"

    log_error "Analyzing installation error"

    if echo "$output" | grep -qi "disk.*full\|no space left"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: Disk Full"
        gum style --foreground 242 "The target disk is full or too small."

    elif echo "$output" | grep -qi "network.*error\|connection.*reset\|timeout"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: Network Error"
        gum style --foreground 242 "Connection interrupted during installation."
        echo ""
        gum style --foreground 242 "Try:"
        gum style --foreground 242 "  • Check network stability"
        gum style --foreground 242 "  • Use a wired connection"
        gum style --foreground 242 "  • Run the installer again"

    elif echo "$output" | grep -qi "flake.*lock\|git\|github"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: Flake/Lock File Issue"
        gum style --foreground 242 "Problem accessing or building the flake."
        echo ""
        gum style --foreground 242 "Try:"
        gum style --foreground 242 "  • Run: nix flake check"
        gum style --foreground 242 "  • Update flake.lock: nix flake update"
        gum style --foreground 242 "  • Ensure git repo is clean"

    elif echo "$output" | grep -qi "hardware.*config\|facter"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: Hardware Detection Failed"
        gum style --foreground 242 "nixos-facter could not detect hardware properly."
        echo ""
        gum style --foreground 242 "Try:"
        gum style --foreground 242 "  • Ensure target is booted from NixOS USB"
        gum style --foreground 242 "  • Check that target has internet access"
        gum style --foreground 242 "  • Run with --debug for more details"

    elif echo "$output" | grep -qi "disko\|partition\|filesystem"; then
        gum style --foreground 214 --bold "🔍 Diagnosis: Disk Partitioning Failed"
        gum style --foreground 242 "Could not partition or format the disk."
        echo ""
        gum style --foreground 242 "Try:"
        gum style --foreground 242 "  • Verify disk is not in use: lsblk on target"
        gum style --foreground 242 "  • Check disk for errors: smartctl -a $DISK"
        gum style --foreground 242 "  • Ensure you have sufficient privileges"

    else
        gum style --foreground 214 --bold "🔍 Diagnosis: Unknown Installation Error"
        gum style --foreground 242 "Check the output above for specific error messages."
        echo ""
        gum style --foreground 242 "Common causes:"
        gum style --foreground 242 "  • Nix evaluation error in flake"
        gum style --foreground 242 "  • Missing dependencies on target"
        gum style --foreground 242 "  • SSH connection interrupted"
    fi
}

# Success message
show_success() {
    local target_ip
    target_ip=$(echo "$TARGET" | cut -d'@' -f2)
    
    gum style \
        --border double \
        --align center \
        --width 60 \
        --margin "1 2" \
        --padding "2 2" \
        "$(gum style --foreground 82 --bold "✓ Installation Complete!")" \
        "" \
        "$(gum style --foreground 255 "Hostname: $HOSTNAME")" \
        "$(gum style --foreground 255 "Type: $TYPE")" \
        "" \
        "$(gum style --foreground 242 "SSH fingerprints:")"
    
    ssh-keygen -lf "$TEMP_DIR/etc/ssh/ssh_host_ed25519_key.pub" | awk '{print "  ED25519: " $2}'
    ssh-keygen -lf "$TEMP_DIR/etc/ssh/ssh_host_rsa_key.pub" | awk '{print "  RSA:     " $2}'
    
    gum style \
        --align center \
        --width 60 \
        --margin "1 0" \
        "" \
        "$(gum style --foreground 242 "Next steps:")" \
        "$(gum style "ssh root@$target_ip")" \
        ""
    
    if [[ "$AUTO_UPDATE" == true ]]; then
        gum style --foreground 242 "Auto-updates configured from $FLAKE_REPO at $UPDATE_TIME"
    fi
}

# Main execution
main() {
    # Initialize log file with header
    {
        echo "============================================"
        echo "NixOS Cattle Installer - Debug Log"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Log File: $LOG_FILE"
        echo "============================================"
        echo ""
    } >> "$LOG_FILE"

    log_info "=== NixOS Cattle Installer Starting ==="
    log_info "Script directory: $SCRIPT_DIR"
    log_info "Flake directory: $FLAKE_DIR"
    log_info "Debug mode: $DEBUG_MODE"
    log_info "Log file: $LOG_FILE"

    check_gum
    show_welcome
    get_ssh_connection
    select_machine_type
    get_hostname
    select_disk
    configure_autoupdate
    confirm_and_install

    log_info "=== Installation Complete ==="
}

# Run main
main "$@"
