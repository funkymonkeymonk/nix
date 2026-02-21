#!/usr/bin/env bash
#
# Bootstrap script for Nix system configuration
#
# This script:
# 1. Checks if Nix is installed (installs if not)
# 2. Installs the core configuration with essential tools (devenv, direnv, etc.)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/funkymonkeymonk/nix/main/bootstrap.sh | bash
#   or
#   ./bootstrap.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin)
            echo "darwin"
            ;;
        Linux)
            echo "linux"
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac
}

# Check if Nix is installed
check_nix() {
    if command -v nix &> /dev/null; then
        return 0
    fi
    return 1
}

# Install Nix using Determinate Systems installer
install_nix() {
    info "Installing Nix using Determinate Systems installer..."
    
    # The Determinate Systems installer handles all platforms and provides
    # good defaults including enabling flakes
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    
    # Source nix profile for current shell
    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    elif [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    
    success "Nix installed successfully"
}

# Install the core configuration
install_core() {
    local os
    os=$(detect_os)
    
    info "Installing core configuration..."
    
    # Clone the repository if not already in it
    if [ ! -f "flake.nix" ]; then
        info "Cloning nix configuration repository..."
        REPO_DIR="${HOME}/.config/nix-config"
        
        if [ -d "$REPO_DIR" ]; then
            warn "Repository already exists at $REPO_DIR, updating..."
            cd "$REPO_DIR"
            git pull
        else
            git clone https://github.com/funkymonkeymonk/nix.git "$REPO_DIR"
            cd "$REPO_DIR"
        fi
    fi
    
    if [ "$os" = "darwin" ]; then
        info "Building and switching to core Darwin configuration..."
        
        # First time setup requires bootstrapping nix-darwin
        if ! command -v darwin-rebuild &> /dev/null; then
            info "Bootstrapping nix-darwin..."
            nix run nix-darwin/master#darwin-rebuild -- switch --flake .#core
        else
            darwin-rebuild switch --flake .#core
        fi
        
        success "Core configuration installed successfully!"
    else
        warn "NixOS bootstrap requires hardware-specific configuration."
        info "For NixOS systems:"
        echo "  1. Install NixOS using the standard installer"
        echo "  2. Clone this repo: git clone https://github.com/funkymonkeymonk/nix.git"
        echo "  3. Create a target with your hardware-configuration.nix in targets/<hostname>/"
        echo "  4. Add your configuration to flake.nix"
        echo "  5. Apply with: sudo nixos-rebuild switch --flake .#<your-target>"
        echo ""
        info "Essential packages can be installed via nix profile:"
        echo "  nix profile install nixpkgs#devenv nixpkgs#direnv nixpkgs#git"
        
        success "Repository cloned. Follow the steps above to complete NixOS setup."
    fi
}

# Main script
main() {
    echo ""
    echo "========================================"
    echo "  Nix System Configuration Bootstrap   "
    echo "========================================"
    echo ""
    
    local os
    os=$(detect_os)
    info "Detected OS: $os"
    
    # Check for Nix installation
    if check_nix; then
        success "Nix is already installed"
        nix --version
    else
        warn "Nix is not installed"
        install_nix
    fi
    
    # Verify Nix is working
    if ! check_nix; then
        error "Nix installation failed or not in PATH. Please restart your shell and try again."
    fi
    
    # Install core configuration
    install_core
    
    echo ""
    success "Bootstrap complete!"
    echo ""
    info "Next steps:"
    echo "  1. Restart your shell or run: exec \$SHELL"
    echo "  2. Navigate to your nix config: cd ~/.config/nix-config"
    echo "  3. Customize your configuration and run: devenv tasks run switch"
    echo ""
    info "Available tools installed:"
    echo "  - devenv: Development environment manager"
    echo "  - direnv: Automatic environment loading"
    echo "  - git, gh: Git and GitHub CLI"
    echo "  - vim, bat, ripgrep, fd, jq: Essential CLI tools"
    echo ""
}

main "$@"
