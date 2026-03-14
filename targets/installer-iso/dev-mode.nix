# Dev mode script for NixOS Installer ISO
# Checks kernel parameters for dev mode and fetches latest installer
{pkgs, ...}:
pkgs.writeScriptBin "nixos-installer-dev-mode" ''
  #!${pkgs.bash}/bin/bash
  set -euo pipefail

  # Colors
  YELLOW='\033[1;33m'
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  NC='\033[0m'

  log_info() { echo -e "''${BLUE}[INFO]''${NC} $1"; }
  log_success() { echo -e "''${GREEN}[SUCCESS]''${NC} $1"; }
  log_warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }
  log_error() { echo -e "''${RED}[ERROR]''${NC} $1"; }

  # Check kernel parameters for dev mode
  check_dev_mode() {
    local cmdline
    cmdline=$(cat /proc/cmdline)

    # Check for installer-branch parameter
    if echo "$cmdline" | grep -qE 'installer-branch=[^ ]+'; then
      local branch
      branch=$(echo "$cmdline" | grep -oE 'installer-branch=[^ ]+' | cut -d= -f2)
      echo "$branch"
      return 0
    fi

    # Check for dev-mode flag (uses main branch by default)
    if echo "$cmdline" | grep -qE '(^| )dev-mode( |$)'; then
      echo "main"
      return 0
    fi

    return 1
  }

  # Fetch and run dev installer
  run_dev_installer() {
    local branch="$1"

    echo ""
    log_warn "=========================================="
    log_warn "     DEV MODE ENABLED"
    log_warn "=========================================="
    log_info "Branch: $branch"
    log_info "Fetching latest installer from GitHub..."
    echo ""

    local installer_url="https://raw.githubusercontent.com/funkymonkeymonk/nix/$branch/targets/installer-iso/installer.nix"
    local temp_installer="/tmp/dev-installer.nix"

    # Download the installer
    if ! curl -fsSL "$installer_url" -o "$temp_installer" 2>/dev/null; then
      log_error "Failed to download installer from: $installer_url"
      log_warn "Falling back to bundled installer..."
      sleep 3
      return 1
    fi

    log_success "Downloaded installer script"
    log_info "Building dev installer (this may take a moment)..."
    echo ""

    # Build the installer
    local build_result="/tmp/dev-installer-result"
    if ! ${pkgs.nix}/bin/nix build \
      --impure \
      --extra-experimental-features "nix-command flakes" \
      --expr "(import <nixpkgs> {}).callPackage $temp_installer {}" \
      --out-link "$build_result" 2>&1 | tee /tmp/dev-build.log; then
      log_error "Failed to build dev installer!"
      log_info "Build log saved to: /tmp/dev-build.log"
      log_warn "Falling back to bundled installer..."
      sleep 3
      return 1
    fi

    if [ -L "$build_result" ] && [ -x "$build_result/bin/nixos-installer-iso" ]; then
      log_success "Dev installer built successfully!"
      echo ""
      log_info "Starting dev installer from branch: $branch"
      echo ""
      sleep 2
      "$build_result/bin/nixos-installer-iso"
      return $?
    else
      log_error "Dev installer binary not found"
      log_warn "Falling back to bundled installer..."
      sleep 3
      return 1
    fi
  }

  # Main
  main() {
    # Check if we're in dev mode
    if branch=$(check_dev_mode); then
      if run_dev_installer "$branch"; then
        exit 0
      fi
      # If dev mode failed, fall through to bundled installer
    fi

    # Run bundled installer
    exec ${pkgs.nixos-flake-installer}/bin/nixos-installer-iso "$@"
  }

  main "$@"
''
