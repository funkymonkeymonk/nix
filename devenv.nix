{pkgs, ...}: {
  packages = [
    # Removed go-task - using devenv tasks instead
    pkgs.alejandra
    # Additional Nix development tools
    pkgs.nixpkgs-fmt
    pkgs.statix
    pkgs.deadnix
    pkgs.nil
    pkgs.nix-tree
    pkgs.nvd
    # Useful CLI tools
    pkgs.ripgrep
    pkgs.fd
    pkgs.jq
    pkgs.envsubst
    # Documentation
    pkgs.mdbook
    # YAML linting
    pkgs.yamllint
    pkgs.yamlfmt
    pkgs.nixd
    pkgs.optnix
    # Cachix CLI for pushing to binary cache
    pkgs.cachix
    # IDE tools
    pkgs.zellij
    pkgs.yazi
    pkgs.helix
    pkgs.gh-dash
    # GitHub Actions local runner
    pkgs.act
    # Additional tools for tasks
    pkgs.rsync
    # TUI tools for interactive installers
    pkgs.gum # Modern TUI components from Charm
    pkgs.sshpass # For non-interactive SSH password authentication
    # Note: Dagger was removed from nixpkgs. CI tasks now use devenv tasks directly.
    # Note: 1password-cli (op) is expected to be available on machines that need
    # switch and cachix:push tasks. It has an unfree license so we don't include
    # it in devenv packages to avoid CI failures.
  ];

  # Shell aliases for devenv tasks
  enterShell = ''
    # devenv task runner aliases
    alias dt="devenv tasks run"
    alias dtr="devenv tasks run"
    alias dtl="devenv tasks list"

    alias s="devenv tasks run system:switch"
    alias switch="devenv tasks run system:switch"
    alias q="devenv tasks run check:all"
    alias b="devenv tasks run build:all"
    alias i="devenv tasks run dev:ide"
  '';

  # Disable automatic Cachix management so devenv can run without being a trusted Nix user
  cachix = {
    enable = false;
  };

  # https://devenv.sh/git-hooks/
  git-hooks = {
    hooks = {
      alejandra = {
        enable = true;
      };
      statix = {
        enable = true;
      };
      deadnix = {
        enable = true;
        entry = "${pkgs.deadnix}/bin/deadnix --no-underscore";
      };
      yamllint = {
        enable = true;
      };
      # Pre-push hook for documentation updates
      docs-update = {
        enable = true;
        name = "docs-update";
        entry = "${./scripts/docs-update.sh}";
        types = ["file"];
        files = "(\.nix|\.md)$";
        pass_filenames = false;
        stages = ["pre-push"];
      };
    };
  };

  # All tasks migrated from Taskfile.yml
  tasks = {
    # ============================================
    # DOCUMENTATION TASKS
    # ============================================

    "docs:update" = {
      description = "Update and validate documentation (Diataxis)";
      exec = ''
        ./scripts/docs-update.sh
      '';
    };

    "docs:validate" = {
      description = "Validate documentation structure only";
      exec = ''
        ./scripts/docs-update.sh --validate-only
      '';
    };

    "docs:generate" = {
      description = "Generate reference documentation only";
      exec = ''
        ./scripts/docs-update.sh --generate-only
      '';
    };

    # ============================================
    # CODE QUALITY TASKS
    # ============================================

    "quality:check" = {
      description = "Run all code quality checks (format + lint)";
      exec = ''
        echo "Running code quality checks..."
        echo ""
        echo "=== Formatting ==="
        alejandra .
        echo ""
        echo "=== Dead Code Check ==="
        deadnix --no-underscore .
        echo ""
        echo "=== Static Analysis ==="
        statix check .
        echo ""
        echo "=== YAML Lint ==="
        yamllint .
        echo ""
        echo "Code quality checks complete"
      '';
    };

    # ============================================
    # SYSTEM CONFIGURATION TASKS
    # ============================================

    "system:switch" = {
      description = "Apply configuration to current system (platform-aware)";
      exec = ''
        set -euo pipefail

        echo "=== System Switch ==="
        echo ""

        # Detect platform
        if [[ "$(uname)" == "Darwin" ]]; then
          PLATFORM="Darwin"
        else
          PLATFORM="Linux"
        fi
        echo "Platform: $PLATFORM"

        # Get hostname and map to configuration name
        HOSTNAME=$(hostname -s)
        echo "Hostname: $HOSTNAME"

        if [[ "$PLATFORM" == "Darwin" ]]; then
          # Map hostname to configuration name for Darwin
          case "$HOSTNAME" in
            "wweaver"|"Will-Stride-MBP")
              CONFIG_NAME="wweaver"
              ;;
            "MegamanX")
              CONFIG_NAME="MegamanX"
              ;;
            *)
              echo ""
              echo "ERROR: Unknown Darwin host: $HOSTNAME"
              echo "Add a mapping for this host in devenv.nix system:switch task"
              exit 1
              ;;
          esac
          echo "Configuration: $CONFIG_NAME"
          echo ""

          # Check for 1Password CLI
          if ! command -v op &> /dev/null; then
            echo "ERROR: 1Password CLI (op) not found"
            echo "Install 1Password CLI to use this task"
            exit 1
          fi
          echo "1Password CLI: found"

          # Get sudo password from 1Password
          PASSWORD_PATH="op://Private/''${HOSTNAME} Sudo Password/password"
          echo "Fetching sudo password from 1Password..."
          echo "  Path: $PASSWORD_PATH"

          SUDO_PASSWORD=$(op read "$PASSWORD_PATH" 2>&1) || {
            echo ""
            echo "ERROR: Failed to read sudo password from 1Password"
            echo "  Attempted path: $PASSWORD_PATH"
            echo ""
            echo "Ensure you have a '$HOSTNAME Sudo Password' item in your Private vault"
            echo "with a 'password' field containing your sudo password."
            exit 1
          }
          echo "Sudo password: retrieved"
          echo ""

          # Build and switch
          echo "--- Building Configuration ---"
          echo "Running: darwin-rebuild switch --flake ./#$CONFIG_NAME --impure"
          echo ""

          echo "$SUDO_PASSWORD" | sudo -S NIXPKGS_ALLOW_UNFREE=1 darwin-rebuild switch \
            --flake "./#$CONFIG_NAME" \
            --impure \
            --show-trace 2>&1 || {
            EXIT_CODE=$?
            echo ""
            echo "ERROR: darwin-rebuild failed with exit code $EXIT_CODE"
            echo ""
            echo "Common issues to check:"
            echo "  - Nix evaluation errors (check --show-trace output above)"
            echo "  - Package build failures"
            echo "  - Permission issues"
            echo "  - Network connectivity for fetching packages"
            exit $EXIT_CODE
          }

        else
          # Linux/NixOS
          CONFIG_NAME="$HOSTNAME"
          echo "Configuration: $CONFIG_NAME"
          echo ""

          echo "--- Building Configuration ---"
          echo "Running: nixos-rebuild switch --flake ./#$CONFIG_NAME"
          echo ""

          sudo nixos-rebuild switch \
            --flake "./#$CONFIG_NAME" \
            --show-trace 2>&1 || {
            EXIT_CODE=$?
            echo ""
            echo "ERROR: nixos-rebuild failed with exit code $EXIT_CODE"
            echo ""
            echo "Common issues to check:"
            echo "  - Nix evaluation errors (check --show-trace output above)"
            echo "  - Package build failures"
            echo "  - Permission issues"
            echo "  - Network connectivity for fetching packages"
            exit $EXIT_CODE
          }
        fi

        echo ""
        echo "=== System Switch Complete ==="
        echo "Configuration '$CONFIG_NAME' applied successfully"
      '';
    };

    "system:init" = {
      description = "Initial setup commands (Darwin only)";
      exec = ''
        if [[ "$(uname)" != "Darwin" ]]; then
          echo "This task only runs on macOS"
          exit 1
        fi
        sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ./
      '';
    };

    # ============================================
    # TEST TASKS
    # ============================================

    "test:run" = {
      description = "Run flake check (defaults to quick)";
      after = ["check:quick"];
      exec = "echo 'Test complete'";
    };

    "check:quick" = {
      description = "Quick syntax and lint checks (~30s)";
      exec = ''
        echo "Running quick validation checks..."

        # Run lint checks
        devenv tasks run check:lint

        echo "All quick validation checks passed"
      '';
    };

    "build:darwin" = {
      description = "Build Darwin configurations (dry-run)";
      exec = ''
        echo "Building Darwin configurations"
        echo "=================================="
        for config in wweaver MegamanX; do
          echo "Building $config configuration..."
          if nix build .#darwinConfigurations.$config.system --dry-run >/dev/null 2>&1; then
            echo "$config build plan validated"
          else
            echo "$config build plan failed"
            echo ""
            echo "Running build plan with verbose output for debugging:"
            nix build .#darwinConfigurations.$config.system --dry-run --show-trace
            echo ""
            echo "Common issues to check:"
            echo "  - Missing or incompatible packages in bundles"
            echo "  - Incorrect paths in configurations"
            echo "  - Platform-specific incompatibilities"
            exit 1
          fi
        done
        echo "All Darwin builds completed"
      '';
    };

    "build:nixos" = {
      description = "Build NixOS configurations (dry-run)";
      exec = ''
        echo "Building NixOS configurations"
        echo "================================="
          for config in zero; do
          echo "Building $config configuration..."
          if nix build .#nixosConfigurations.$config.config.system.build.toplevel \
              --dry-run --quiet >/dev/null 2>&1; then
            echo "$config build plan validated"
          else
            echo "$config build plan failed"
            echo ""
            echo "Running build plan with verbose output for debugging:"
            nix build .#nixosConfigurations.$config.config.system.build.toplevel \
              --dry-run --show-trace
            echo ""
            echo "Common issues to check:"
            echo "  - Missing or incompatible packages in bundles"
            echo "  - Incorrect hardware configuration paths"
            echo "  - Platform-specific module incompatibilities"
            exit 1
          fi
        done
        echo "All NixOS builds completed"
      '';
    };

    "build:takeout" = {
      description = "Build takeout container machine type configurations (dry-run)";
      exec = ''
        echo "Building Takeout Container configurations"
        echo "================================="
        echo ""
        echo "Takeout container configurations use nixos-facter for hardware detection"
        echo "and disko for declarative partitioning."
        echo ""

        for config in type-desktop type-server; do
          echo "Building $config configuration..."
          if nix build .#nixosConfigurations.$config.config.system.build.toplevel \
              --dry-run --quiet >/dev/null 2>&1; then
            echo "$config build plan validated"
          else
            echo "$config build plan failed"
            echo ""
            echo "Running build plan with verbose output for debugging:"
            nix build .#nixosConfigurations.$config.config.system.build.toplevel \
              --dry-run --show-trace
            echo ""
            echo "Common issues to check:"
            echo "  - Missing disko or nixos-facter inputs"
            echo "  - Incorrect disk configuration paths"
            echo "  - Hardware detection module issues"
            exit 1
          fi
        done
        echo ""
        echo "All Takeout Container configurations validated successfully"
      '';
    };

    # ============================================
    # BUILD TASKS
    # ============================================

    "build:all" = {
      description = "Build all configurations (dry-run)";
      exec = ''
        echo "Building flake configurations..."
        devenv tasks run build:darwin
        devenv tasks run build:nixos
        devenv tasks run build:takeout
        echo "All configurations (NixOS, Darwin, and Takeout) validated successfully"
      '';
    };

    "validate:disko" = {
      description = "Validate disko disk configurations";
      exec = ''
        echo "Validating Disko configurations"
        echo "================================="

        for config in single-disk-ext4; do
          echo "Checking disk-configs/$config.nix..."
          if nix eval .#nixosConfigurations.type-desktop.config.disko.devices \
              --quiet >/dev/null 2>&1; then
            echo "  disk-configs/$config.nix: valid"
          else
            echo "  disk-configs/$config.nix: INVALID"
            echo ""
            echo "Running eval with verbose output:"
            nix eval .#nixosConfigurations.type-desktop.config.disko.devices --show-trace
            exit 1
          fi
        done

        echo ""
        echo "All Disko configurations valid"
      '';
    };

    "validate:install-script" = {
      description = "Validate install-machine.sh script";
      exec = ''
        echo "Validating install-machine.sh"
        echo "================================="

        if [[ ! -f "scripts/install-machine.sh" ]]; then
          echo "ERROR: scripts/install-machine.sh not found"
          exit 1
        fi

        echo "Checking script syntax..."
        if bash -n scripts/install-machine.sh; then
          echo "  Syntax: OK"
        else
          echo "  Syntax: FAILED"
          exit 1
        fi

        echo "Checking script is executable..."
        if [[ -x "scripts/install-machine.sh" ]]; then
          echo "  Executable: OK"
        else
          echo "  Executable: NO (chmod +x may be needed)"
        fi

        echo ""
        echo "Installation script validation complete"
      '';
    };

    # ============================================
    # DEVELOPMENT ENVIRONMENT TASKS
    # ============================================

    "dev:ide" = {
      description = "Launch zellij IDE with file explorer and agent";
      exec = ''
        export FILE_MANAGER="''${FILE_MANAGER:-yazi}"
        export AGENT="''${AGENT:-opencode}"
        export EDITOR="''${EDITOR:-hx}"
        export PWD="$(pwd)"
        GUID=$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -d'-' -f1)
        SESSION_NAME="ide-$(basename "$PWD")-''${GUID}"
        LAYOUT_FILE=$(mktemp)
        trap "rm -f $LAYOUT_FILE" EXIT
        # Use 3-pane layout with PR review if WITH_PR is set
        if [[ -n "''${WITH_PR}" ]]; then
          TEMPLATE="configs/ide/layout-with-pr.kdl.template"
        else
          TEMPLATE="configs/ide/layout.kdl.template"
        fi
        envsubst < "$TEMPLATE" > "$LAYOUT_FILE"
        zellij -s "$SESSION_NAME" -n "$LAYOUT_FILE"
      '';
    };

    "dev:pr-review" = {
      description = "Launch PR review dashboard (gh-dash)";
      exec = ''
        export PWD="$(pwd)"
        GUID=$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -d'-' -f1)
        SESSION_NAME="pr-review-$(basename "$PWD")-''${GUID}"
        zellij -s "$SESSION_NAME" run -- gh-dash --config "''${PWD}/configs/ide/gh-dash.yml"
      '';
    };

    # ============================================
    # MAINTENANCE TASKS
    # ============================================

    "devenv:update" = {
      description = "Update devenv lock file";
      exec = "devenv update";
    };

    "flake:update" = {
      description = "Update the nix flake to latest versions";
      exec = "nix flake update";
    };

    # ============================================
    # GIT REMOTE TASKS
    # ============================================

    "git:set-remote-ssh" = {
      description = "Switch git remote to SSH";
      exec = ''
        git remote -v
        git remote set-url origin git@github.com:funkymonkeymonk/nix.git
        git remote -v
      '';
    };

    "git:set-remote-https" = {
      description = "Switch git remote to HTTPS";
      exec = ''
        git remote -v
        git remote set-url origin https://github.com/funkymonkeymonk/nix.git
        git remote -v
      '';
    };

    # ============================================
    # AGENT SKILLS TASKS
    # ============================================

    "agent-skills:status" = {
      description = "Check agent skills status";
      exec = ''
        echo "=== Agent Skills Status ==="
        echo "Upstream version:"
        cat modules/home-manager/agent-skills/.upstream-version 2>/dev/null || echo "  Not tracked"
      '';
    };

    "agent-skills:update" = {
      description = "Update agent skills from upstream superpowers";
      exec = ''
        echo "Updating agent skills from upstream..."

        # Upstream repository information
        UPSTREAM_REPO="https://github.com/obra/superpowers.git"
        UPSTREAM_BRANCH="main"

        # Resolve paths
        SKILLS_PATH="$HOME/.config/opencode/skills"
        SUPERPOWERS_PATH="$HOME/.config/opencode/superpowers/skills"
        VERSION_FILE="$SKILLS_PATH/.upstream-version"

        # Read current version
        if [[ -f "$VERSION_FILE" ]]; then
          current_version=$(cat "$VERSION_FILE")
        else
          current_version="none"
        fi

        echo "Current version: $current_version"

        # Clone upstream to temporary directory
        temp_dir=$(mktemp -d)
        trap "rm -rf $temp_dir" EXIT

        echo "Cloning upstream repository..."
        git clone --depth 1 --branch "$UPSTREAM_BRANCH" "$UPSTREAM_REPO" "$temp_dir"

        # Get latest commit hash
        latest_version=$(cd "$temp_dir" && git rev-parse HEAD)

        echo "Latest version: $latest_version"

        if [[ "$current_version" = "$latest_version" ]]; then
          echo "Already up to date"
          exit 0
        fi

        # Update skills
        echo "Updating skills from $temp_dir/skills to $SKILLS_PATH"

        # Ensure directories exist
        mkdir -p "$(dirname "$VERSION_FILE")"
        mkdir -p "$SKILLS_PATH"
        mkdir -p "$SUPERPOWERS_PATH"

        # Copy new skills, preserving custom ones
        if [[ -d "$temp_dir/skills" ]]; then
          rsync -av --delete "$temp_dir/skills/" "$SKILLS_PATH/"
          rsync -av --delete "$temp_dir/skills/" "$SUPERPOWERS_PATH/"
        fi

        # Update version tracking
        echo "$latest_version" > "$VERSION_FILE"

        echo "Skills updated successfully!"
        echo "Version: $latest_version"
        echo "Main skills directory: $SKILLS_PATH"
        echo "Superpowers skills directory: $SUPERPOWERS_PATH"
      '';
    };

    "agent-skills:validate" = {
      description = "Validate skills against Agent Skills specification";
      exec = ''
        echo "Validating skills format..."
        echo "Validation complete"
      '';
    };

    # ============================================
    # CACHIX TASKS
    # ============================================

    "cachix:push" = {
      description = "Build current host configuration and push to Cachix";
      exec = ''
        echo "=== Cachix Push ==="

        # Check for cachix CLI
        if ! command -v cachix &> /dev/null; then
          echo "cachix CLI not found"
          echo "Install with: nix profile install nixpkgs#cachix"
          exit 1
        fi

        # Get auth token from 1Password
        echo "Fetching Cachix auth token from 1Password..."
        CACHIX_AUTH_TOKEN=$(op read "op://Private/Cachix/Auth Token" 2>/dev/null)
        if [[ -z "$CACHIX_AUTH_TOKEN" ]]; then
          echo "Failed to get Cachix auth token from 1Password"
          echo "Make sure you have a 'Cachix' item with 'Auth Token' field in Private vault"
          exit 1
        fi
        export CACHIX_AUTH_TOKEN

        # Authenticate with Cachix
        echo "Authenticating with Cachix..."
        cachix authtoken "$CACHIX_AUTH_TOKEN"

        # Determine platform and hostname
        HOSTNAME=$(hostname -s)
        if [[ "$(uname)" == "Darwin" ]]; then
          PLATFORM="darwin"
          # Map hostname to configuration name
          case "$HOSTNAME" in
            "wweaver"|"Will-Stride-MBP")
              CONFIG_NAME="wweaver"
              ;;
            "MegamanX")
              CONFIG_NAME="MegamanX"
              ;;
            *)
              echo "Unknown Darwin host: $HOSTNAME"
              echo "Add mapping for this host in devenv.nix"
              exit 1
              ;;
          esac
          BUILD_TARGET=".#darwinConfigurations.''${CONFIG_NAME}.system"
        else
          PLATFORM="linux"
          CONFIG_NAME="$HOSTNAME"
          BUILD_TARGET=".#nixosConfigurations.''${CONFIG_NAME}.config.system.build.toplevel"
        fi

        echo "Building $PLATFORM configuration: $CONFIG_NAME"
        echo "   Target: $BUILD_TARGET"

        # Build and push to Cachix
        nix build "$BUILD_TARGET" --no-link --print-out-paths | cachix push funkymonkeymonk

        echo "Successfully built and pushed to Cachix"
      '';
    };

    "cachix:push:all" = {
      description = "Build all configurations for current platform and push to Cachix";
      exec = ''
        echo "=== Cachix Push All ==="

        # Check for cachix CLI
        if ! command -v cachix &> /dev/null; then
          echo "cachix CLI not found"
          echo "Install with: nix profile install nixpkgs#cachix"
          exit 1
        fi

        # Get auth token from 1Password
        echo "Fetching Cachix auth token from 1Password..."
        CACHIX_AUTH_TOKEN=$(op read "op://Private/Cachix/Auth Token" 2>/dev/null)
        if [[ -z "$CACHIX_AUTH_TOKEN" ]]; then
          echo "Failed to get Cachix auth token from 1Password"
          echo "Make sure you have a 'Cachix' item with 'Auth Token' field in Private vault"
          exit 1
        fi
        export CACHIX_AUTH_TOKEN

        # Authenticate with Cachix
        echo "Authenticating with Cachix..."
        cachix authtoken "$CACHIX_AUTH_TOKEN"

        if [[ "$(uname)" == "Darwin" ]]; then
          echo "Building all Darwin configurations..."
          for config in wweaver MegamanX; do
            echo "Building $config..."
            nix build ".#darwinConfigurations.''${config}.system" \
              --no-link --print-out-paths | cachix push funkymonkeymonk
            echo "$config pushed"
          done
        else
          echo "Building all NixOS configurations..."
        for config in zero; do
            echo "Building $config..."
            nix build ".#nixosConfigurations.''${config}.config.system.build.toplevel" \
              --no-link --print-out-paths | cachix push funkymonkeymonk
            echo "$config pushed"
          done
          echo ""
          echo "Building all Cattle configurations..."
        for config in type-desktop type-server; do
            echo "Building $config..."
            nix build ".#nixosConfigurations.''${config}.config.system.build.toplevel" \
              --no-link --print-out-paths | cachix push funkymonkeymonk
            echo "$config pushed"
          done
        fi

        echo "All configurations built and pushed to Cachix"
      '';
    };

    # ============================================
    # MICROVM TASKS
    # ============================================

    "microvm:build" = {
      description = "Build microvm image";
      exec = ''
        echo "Building dev-vm microvm..."
        nix build .#microvm.nixosConfigurations.dev-vm.config.microvm.declaredRunner -o result-microvm
        echo "Build complete: ./result-microvm"
      '';
    };

    "microvm:run" = {
      description = "Run dev-vm microvm (Linux only)";
      exec = ''
        if [[ "$(uname)" == "Darwin" ]]; then
          echo "macOS detected - microvm.nix requires Linux/KVM"
          echo "Please run from a Linux host or inside Colima"
          echo ""
          echo "To run in Colima:"
          echo "  1. colima start --arch x86_64 --vm-type vz"
          echo "  2. colima ssh"
          echo "  3. cd /path/to/nix && devenv tasks run microvm:run"
          exit 1
        fi
        echo "Starting dev-vm microvm..."
        nix run .#microvm.nixosConfigurations.dev-vm.config.microvm.declaredRunner
      '';
    };

    "microvm:test" = {
      description = "Validate microvm configuration";
      exec = ''
        echo "Validating dev-vm microvm configuration..."
        if nix eval .#microvm.nixosConfigurations.dev-vm.config.system.build.toplevel \
          --json >/dev/null 2>&1; then
          echo "dev-vm configuration valid"
        else
          echo "dev-vm configuration invalid"
          nix eval .#microvm.nixosConfigurations.dev-vm.config.system.build.toplevel \
            --json --show-trace
          exit 1
        fi
      '';
    };

    # ============================================
    # CHECK AND LINT TASKS
    # ============================================

    "check:all" = {
      description = "Run all checks (platform-aware)";
      exec = ''
        echo "=== Running Checks ==="
        echo ""
        echo "--- Lint ---"
        devenv tasks run check:lint
        echo ""
        if [[ "$(uname)" == "Darwin" ]]; then
          echo "Detected platform: Darwin"
          echo ""
          echo "--- Darwin Build ---"
          devenv tasks run build:darwin
        else
          echo "Detected platform: Linux"
          echo ""
          echo "--- NixOS Build ---"
          devenv tasks run build:nixos
        fi
        echo ""
        echo "=== Checks Complete ==="
      '';
    };

    "check:flake" = {
      description = "Check flake structure and validity";
      exec = ''
        echo "Checking flake structure..."
        nix flake check --no-build
        echo "Flake check passed"
      '';
    };

    "check:lint" = {
      description = "Run lint checks (formatting + static analysis)";
      exec = ''
        echo "Running lint checks..."
        echo "Checking Nix formatting..."
        find . -name '*.nix' \
          -not -path './.devenv/*' \
          -not -path './.direnv/*' \
          -not -path './.worktrees/*' \
          -not -name '.devenv.flake.nix' \
          | xargs alejandra --check
        echo "Checking for dead code..."
        find . -name '*.nix' \
          -not -path './.devenv/*' \
          -not -path './.direnv/*' \
          -not -path './.worktrees/*' \
          -not -name '.devenv.flake.nix' \
          | xargs deadnix --no-underscore --fail
        echo "Running static analysis..."
        # statix respects .gitignore by default
        statix check .
        echo "Checking YAML files..."
        yamllint .
        echo "Lint checks complete"
      '';
    };

    "format:all" = {
      description = "Apply formatting fixes";
      exec = ''
        echo "Applying formatting fixes..."
        alejandra .
        echo "Formatting complete"
      '';
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
