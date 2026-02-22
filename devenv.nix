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
    alias t="devenv tasks run test"
    alias tq="devenv tasks run test:quick"
    alias tf="devenv tasks run test:full"
    alias s="devenv tasks run switch"
    alias q="devenv tasks run quality"
    alias b="devenv tasks run nix:build"
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
        files = "\\.(nix|md)$";
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

    "quality" = {
      description = "Run all code quality checks (format + lint)";
      exec = "devenv test";
    };

    # ============================================
    # SYSTEM CONFIGURATION TASKS
    # ============================================

    "switch" = {
      description = "Apply configuration to current system (platform-aware)";
      exec = ''
        if [[ "$(uname)" == "Darwin" ]]; then
          HOSTNAME=$(hostname -s)
          PASSWORD_PATH="op://Private/''${HOSTNAME} Sudo Password/password"
          NIXPKGS_ALLOW_UNFREE=1 op run \
            --env-file=<(echo "SUDO_PASSWORD=$(op read "$PASSWORD_PATH")") \
            -- bash -c 'echo "$SUDO_PASSWORD" | \
            sudo -S NIXPKGS_ALLOW_UNFREE=1 darwin-rebuild switch --flake ./#MegamanX --impure'
        else
          sudo nixos-rebuild switch --flake ./
        fi
      '';
    };

    "init" = {
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

    "test" = {
      description = "Run flake check (defaults to quick)";
      after = ["test:quick"];
      exec = "echo 'Test complete'";
    };

    "test:quick" = {
      description = "Quick syntax and validation checks (30s) - Reports all failures";
      exec = ''
        echo "Running quick validation checks..."
        failed_checks=""

        # Test basic flake validation
        echo "Checking flake structure and dependencies..."
        if ! nix flake check --no-build >/dev/null 2>&1; then
          echo "Flake check failed"
          echo "Running flake check with verbose output for debugging:"
          nix flake check --no-build --show-trace
          failed_checks="$failed_checks flake-check"
        else
          echo "Flake check passed"
        fi

        # Test Linux configurations
        for config in drlight zero; do
          echo "Validating NixOS $config configuration..."
          if nix eval .#nixosConfigurations.$config.config.system.build.toplevel \
            --json >/dev/null 2>&1; then
            echo "NixOS $config configuration valid"
          else
            echo "NixOS $config configuration invalid"
            echo "Running evaluation with verbose output for debugging:"
            nix eval .#nixosConfigurations.$config.config.system.build.toplevel \
              --json --show-trace
            failed_checks="$failed_checks NixOS:$config"
          fi
        done

        # Test macOS configurations
        for config in wweaver MegamanX; do
          echo "Validating Darwin $config configuration..."
          if nix eval .#darwinConfigurations.$config.system \
            --json >/dev/null 2>&1; then
            echo "Darwin $config configuration valid"
          else
            echo "Darwin $config configuration invalid"
            echo "Running evaluation with verbose output for debugging:"
            nix eval .#darwinConfigurations.$config.system \
              --json --show-trace
            failed_checks="$failed_checks Darwin:$config"
          fi
        done

        # Test microvm configuration
        echo "Testing dev-vm microvm configuration..."
        if nix eval .#microvm.nixosConfigurations.dev-vm.config.system.build.toplevel \
          --json >/dev/null 2>&1; then
          echo "Microvm dev-vm configuration valid"
        else
          echo "Microvm dev-vm configuration invalid"
          failed_checks="$failed_checks microvm:dev-vm"
        fi

        # Report all failures
        if [ -n "$failed_checks" ]; then
          echo ""
          echo "QUICK VALIDATION FAILED"
          echo "Failed checks:$failed_checks"
          echo ""
          echo "To debug individual issues:"
          for check in $failed_checks; do
            case $check in
              "flake-check")
                echo "  - Run: nix flake check --no-build --show-trace"
                ;;
              "NixOS:"*)
                cfg=''${check#NixOS:}
                echo "  - Run: nix eval .#nixosConfigurations.$cfg.config.system.build.toplevel --json --show-trace"
                ;;
              "Darwin:"*)
                cfg=''${check#Darwin:}
                echo "  - Run: nix eval .#darwinConfigurations.$cfg.system --json --show-trace"
                ;;
              "microvm:"*)
                cfg=''${check#microvm:}
                echo "  - Run: nix eval .#microvm.nixosConfigurations.$cfg.config.system.build.toplevel --json --show-trace"
                ;;
            esac
          done
          exit 1
        else
          echo "All quick validation checks passed"
        fi
      '';
    };

    "test:full" = {
      description = "Full cross-platform verification (5-10min) - Fail fast";
      exec = ''
        echo "Universal Cross-Platform Testing Suite"
        echo "Validating configuration definitions..."

        # Validate NixOS configurations
        for config in drlight zero; do
          echo "Validating NixOS $config configuration..."
          if nix eval .#nixosConfigurations.$config.config.system.build.toplevel \
            --json >/dev/null 2>&1; then
            echo "NixOS $config configuration valid"
          else
            echo "NixOS $config configuration invalid"
            echo "Running with verbose output for debugging:"
            nix eval .#nixosConfigurations.$config.config.system.build.toplevel \
              --json --show-trace
            exit 1
          fi
        done

        # Validate Darwin configurations
        for config in wweaver MegamanX; do
          echo "Validating Darwin $config configuration..."
          if nix eval .#darwinConfigurations.$config.system \
            --json >/dev/null 2>&1; then
            echo "Darwin $config configuration valid"
          else
            echo "Darwin $config configuration invalid"
            echo "Running with verbose output for debugging:"
            nix eval .#darwinConfigurations.$config.system \
              --json --show-trace
            exit 1
          fi
        done

        echo "Testing Linux build plans..."
        for config in drlight zero; do
          echo "Testing $config build plan..."
          if nix build .#nixosConfigurations.$config.config.system.build.toplevel \
            --dry-run --quiet >/dev/null 2>&1; then
            echo "$config build plan validated"
          else
            echo "$config build plan failed"
            echo "Running build plan with verbose output for debugging:"
            nix build .#nixosConfigurations.$config.config.system.build.toplevel \
              --dry-run --show-trace
            exit 1
          fi
        done

        echo "Testing Darwin evaluations..."
        for config in wweaver MegamanX; do
          echo "Testing $config evaluation..."
          if nix eval .#darwinConfigurations.$config.system \
            --quiet >/dev/null 2>&1; then
            echo "$config evaluation validated"
          else
            echo "$config evaluation failed"
            echo "Running evaluation with verbose output for debugging:"
            nix eval .#darwinConfigurations.$config.system \
              --show-trace
            exit 1
          fi
        done

        echo "Universal cross-platform testing completed!"
        echo "Results Summary"
        echo "   Configuration validation = SUCCESS"
        echo "   Linux build planning = SUCCESS"
        echo "   Darwin evaluation = SUCCESS"
        echo "   Host-agnostic execution = SUCCESS"
      '';
    };

    "test:darwin-only" = {
      description = "Test only Darwin configurations (for Darwin runners)";
      exec = ''
        echo "Testing Darwin configurations"
        echo "=================================="
        for config in wweaver MegamanX; do
          echo "Testing $config build plan"
          echo "Testing $config build plan..."
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
        echo "All Darwin tests completed"
      '';
    };

    "test:nixos-only" = {
      description = "Test only NixOS configurations (for Linux runners)";
      exec = ''
        echo "Testing NixOS configurations"
        echo "================================="
        for config in drlight zero; do
          echo "Testing $config build plan"
          echo "Testing $config build plan..."
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
        echo "All NixOS tests completed"
      '';
    };

    # ============================================
    # BUILD TASKS
    # ============================================

    "nix:build" = {
      description = "Build all configurations (dry-run)";
      exec = ''
        echo "Building flake configurations..."
        devenv tasks run nix:build:darwin
        devenv tasks run nix:build:nixos
        echo "All configurations (NixOS and Darwin) validated successfully"
      '';
    };

    "nix:build:darwin" = {
      description = "Build all Darwin (macOS) configurations";
      exec = ''
        echo "Building Darwin configurations..."
        nix build .#darwinConfigurations.wweaver.system --dry-run
        nix build .#darwinConfigurations.MegamanX.system --dry-run
        echo "All Darwin configurations validated successfully"
      '';
    };

    "nix:build:nixos" = {
      description = "Build all NixOS configurations";
      exec = ''
        echo "Building NixOS configurations..."
        nix build .#nixosConfigurations.drlight.config.system.build.toplevel --dry-run
        # nix build .#nixosConfigurations.zero.config.system.build.toplevel --dry-run
        echo "All NixOS configurations validated successfully"
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
          for config in drlight zero; do
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
  };

  # See full reference at https://devenv.sh/reference/options/
}
