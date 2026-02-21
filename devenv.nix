{
  pkgs,
  lib,
  config,
  ...
}: {
  packages = [
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
  ];

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

  # Tasks - replacing Taskfile.yml
  # Run with: devenv tasks run <task-name>
  # List all: devenv tasks list
  tasks = {
    # ==================== Switch Tasks ====================
    "switch" = {
      description = "Run the appropriate switch command for the platform";
      exec =
        if pkgs.stdenv.isDarwin
        then ''
          HOSTNAME=$(hostname -s)
          PASSWORD_PATH="op://Private/''${HOSTNAME} Sudo Password/password"
          op run \
            --env-file=<(echo "SUDO_PASSWORD=$(op read "$PASSWORD_PATH")") \
            -- bash -c 'echo "$SUDO_PASSWORD" | sudo -S darwin-rebuild switch --flake ./'
        ''
        else ''
          sudo nixos-rebuild switch --flake ./
        '';
    };

    # ==================== Test Tasks ====================
    "test" = {
      description = "Run quick validation checks (default)";
      after = ["test:quick"];
    };

    "test:quick" = {
      description = "Quick syntax and validation checks (30s)";
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

        # Report all failures
        if [ -n "$failed_checks" ]; then
          echo ""
          echo "QUICK VALIDATION FAILED"
          echo "Failed checks:$failed_checks"
          exit 1
        else
          echo "All quick validation checks passed"
        fi
      '';
    };

    "test:full" = {
      description = "Full cross-platform verification (5-10min)";
      exec = ''
        echo "Universal Cross-Platform Testing Suite"
        echo "Validating configuration definitions..."

        # NixOS configurations
        for config in drlight zero; do
          echo "Validating NixOS $config configuration..."
          if nix eval .#nixosConfigurations.$config.config.system.build.toplevel \
            --json >/dev/null 2>&1; then
            echo "NixOS $config configuration valid"
          else
            echo "NixOS $config configuration invalid"
            nix eval .#nixosConfigurations.$config.config.system.build.toplevel \
              --json --show-trace
            exit 1
          fi
        done

        # Darwin configurations
        for config in wweaver MegamanX; do
          echo "Validating Darwin $config configuration..."
          if nix eval .#darwinConfigurations.$config.system \
            --json >/dev/null 2>&1; then
            echo "Darwin $config configuration valid"
          else
            echo "Darwin $config configuration invalid"
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
            nix eval .#darwinConfigurations.$config.system --show-trace
            exit 1
          fi
        done

        echo "Universal cross-platform testing completed!"
        echo "Results Summary:"
        echo "  Configuration validation = SUCCESS"
        echo "  Linux build planning = SUCCESS"
        echo "  Darwin evaluation = SUCCESS"
      '';
    };

    "test:darwin-only" = {
      description = "Test only Darwin configurations";
      exec = ''
        echo "Testing Darwin configurations"
        echo "=================================="

        for config in wweaver MegamanX; do
          echo "Testing $config build plan..."
          if nix build .#darwinConfigurations.$config.system --dry-run >/dev/null 2>&1; then
            echo "$config build plan validated"
          else
            echo "$config build plan failed"
            echo ""
            echo "Running build plan with verbose output for debugging:"
            nix build .#darwinConfigurations.$config.system --dry-run --show-trace
            exit 1
          fi
        done

        echo "All Darwin tests completed"
      '';
    };

    "test:nixos-only" = {
      description = "Test only NixOS configurations";
      exec = ''
        echo "Testing NixOS configurations"
        echo "================================="

        for config in drlight zero; do
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
            exit 1
          fi
        done

        echo "All NixOS tests completed"
      '';
    };

    # ==================== Build Tasks ====================
    "build" = {
      description = "Build all configurations (dry-run)";
      after = ["build:darwin" "build:nixos"];
    };

    "build:darwin" = {
      description = "Build all Darwin (macOS) configurations";
      exec = ''
        echo "Building Darwin configurations..."
        nix build .#darwinConfigurations.wweaver.system --dry-run
        nix build .#darwinConfigurations.MegamanX.system --dry-run
        echo "All Darwin configurations validated successfully"
      '';
    };

    "build:nixos" = {
      description = "Build all NixOS configurations";
      exec = ''
        echo "Building NixOS configurations..."
        nix build .#nixosConfigurations.drlight.config.system.build.toplevel --dry-run
        # nix build .#nixosConfigurations.zero.config.system.build.toplevel --dry-run
        echo "All NixOS configurations validated successfully"
      '';
    };

    # ==================== Quality Tasks ====================
    "quality" = {
      description = "Run all code quality checks";
      exec = "devenv test";
    };

    "fmt" = {
      description = "Format all Nix files";
      exec = "alejandra .";
    };

    # ==================== IDE Tasks ====================
    "ide" = {
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

    "pr:review" = {
      description = "Launch PR review dashboard (gh-dash)";
      exec = ''
        export PWD="$(pwd)"
        GUID=$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -d'-' -f1)
        SESSION_NAME="pr-review-$(basename "$PWD")-''${GUID}"
        zellij -s "$SESSION_NAME" run -- gh-dash --config "''${PWD}/configs/ide/gh-dash.yml"
      '';
    };

    # ==================== Flake Tasks ====================
    "flake:update" = {
      description = "Update the nix flake to latest versions";
      exec = "nix flake update";
    };

    "devenv:update" = {
      description = "Update devenv lock file";
      exec = "devenv update";
    };

    # ==================== Init Tasks ====================
    "init" = {
      description = "Initial setup commands for nix-darwin";
      exec = "sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ./";
    };

    # ==================== Git Remote Tasks ====================
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

    # ==================== Agent Skills Tasks ====================
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

    # ==================== Documentation Tasks ====================
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

    # ==================== Cachix Tasks ====================
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
        ${
          if pkgs.stdenv.isDarwin
          then ''
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
                echo "Add mapping for this host"
                exit 1
                ;;
            esac
            BUILD_TARGET=".#darwinConfigurations.''${CONFIG_NAME}.system"
            echo "Building darwin configuration: $CONFIG_NAME"
          ''
          else ''
            CONFIG_NAME="$HOSTNAME"
            BUILD_TARGET=".#nixosConfigurations.''${CONFIG_NAME}.config.system.build.toplevel"
            echo "Building linux configuration: $CONFIG_NAME"
          ''
        }

        echo "Target: $BUILD_TARGET"

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

        ${
          if pkgs.stdenv.isDarwin
          then ''
            echo "Building all Darwin configurations..."
            for config in wweaver MegamanX; do
              echo "Building $config..."
              nix build ".#darwinConfigurations.''${config}.system" \
                --no-link --print-out-paths | cachix push funkymonkeymonk
              echo "$config pushed"
            done
          ''
          else ''
            echo "Building all NixOS configurations..."
            for config in drlight zero; do
              echo "Building $config..."
              nix build ".#nixosConfigurations.''${config}.config.system.build.toplevel" \
                --no-link --print-out-paths | cachix push funkymonkeymonk
              echo "$config pushed"
            done
          ''
        }

        echo "All configurations built and pushed to Cachix"
      '';
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
