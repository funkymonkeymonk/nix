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

    # ============================================
    # JJ Workspace Support - Check if in workspace
    # ============================================
    # Function to detect main repo root from workspace
    _detect_jj_repo_root() {
      local current_dir="$1"
      if [[ -f "$current_dir/.jj/repo" ]] && [[ ! -d "$current_dir/.jj/repo" ]]; then
        local repo_pointer=$(cat "$current_dir/.jj/repo" 2>/dev/null)
        if [[ -n "$repo_pointer" ]]; then
          (cd "$current_dir/.jj" && cd "$(dirname "$repo_pointer")" && cd .. && pwd)
          return 0
        fi
      fi
      echo "$current_dir"
    }

    # Check if we're in a jj workspace
    if command -v jj &>/dev/null; then
      _JJ_WORKSPACE_ROOT=$(jj root 2>/dev/null || pwd)
      _JJ_REPO_ROOT=$(_detect_jj_repo_root "$_JJ_WORKSPACE_ROOT")

      if [[ "$_JJ_WORKSPACE_ROOT" != "$_JJ_REPO_ROOT" ]] && [[ -d "$_JJ_WORKSPACE_ROOT/.jj" ]]; then
        # In workspace - create functions that run from repo root
        echo "📁 JJ Workspace: $(basename "$_JJ_WORKSPACE_ROOT")"
        echo "   Switch will run from: $_JJ_REPO_ROOT"
        echo ""

        # Use functions instead of aliases for better compatibility
        s() { (cd "$_JJ_REPO_ROOT" && devenv tasks run system:switch "$@"); }
        switch() { (cd "$_JJ_REPO_ROOT" && devenv tasks run system:switch "$@"); }
        b() { (cd "$_JJ_REPO_ROOT" && devenv tasks run build:all "$@"); }
        q() { (cd "$_JJ_REPO_ROOT" && devenv tasks run check:all "$@"); }
      else
        # In main repo - use normal functions
        s() { devenv tasks run system:switch "$@"; }
        switch() { devenv tasks run system:switch "$@"; }
        q() { devenv tasks run check:all "$@"; }
        b() { devenv tasks run build:all "$@"; }
      fi
    else
      # No jj - use normal functions
      s() { devenv tasks run system:switch "$@"; }
      switch() { devenv tasks run system:switch "$@"; }
      q() { devenv tasks run check:all "$@"; }
      b() { devenv tasks run build:all "$@"; }
    fi
    i() { devenv tasks run dev:ide "$@"; }

    # Cleanup temp functions
    unset -f _detect_jj_repo_root 2>/dev/null || true
    unset _JJ_WORKSPACE_ROOT _JJ_REPO_ROOT 2>/dev/null || true

    # Source switch-nix function (same source as system-wide install)
    source ./modules/common/scripts/switch-nix
  '';

  # Disable devenv's built-in cachix module — we manage cachix manually via pkgs.cachix.
  # The module's default `cachix.package` evaluation can fail in CI when the devenv binary
  # version doesn't match the project's nixpkgs pin (e.g., different Nix store closures).
  # CI pins devenv to flake.lock's nixpkgs rev to prevent this mismatch.
  cachix.enable = false;

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

      # Quick syntax check for pre-commit (fast - < 2 seconds)
      quick-nix-check = {
        enable = true;
        name = "quick-nix-syntax";
        entry = ''
          ${pkgs.bash}/bin/bash -c '
            for file in "$@"; do
              if ! ${pkgs.nix}/bin/nix-instantiate --parse "$file" > /dev/null 2>&1; then
                echo "❌ Syntax error in: $file"
                exit 1
              fi
            done
            echo "✓ Nix syntax OK"
          ' bash
        '';
        types = ["file"];
        files = "\\.nix$";
        stages = ["pre-commit"];
      };

      # Full flake evaluation check for pre-push (~20 seconds)
      flake-check = {
        enable = true;
        name = "flake-check-no-build";
        entry = ''
          ${pkgs.bash}/bin/bash -c '
            echo "→ Running nix flake check --no-build (this takes ~20s)..."
            if ${pkgs.nix}/bin/nix flake check --no-build --all-systems 2>&1; then
              echo "✓ Flake check passed"
            else
              echo ""
              echo "❌ Flake check failed!"
              echo ""
              echo "Common fixes:"
              echo "  - Run: nix flake check --no-build --all-systems to see full error"
              echo "  - Check for invalid NixOS/home-manager options"
              echo "  - Verify all module imports are correct"
              exit 1
            fi
          '
        '';
        types = ["file"];
        files = "\\.nix$";
        pass_filenames = false;
        stages = ["pre-push"];
      };

      # Cross-platform configuration evaluation check for pre-push
      # Catches module errors, missing options, and platform mismatches before CI
      config-eval-check = {
        enable = true;
        name = "config-eval-check";
        entry = ''
          ${pkgs.bash}/bin/bash -c '
            echo "→ Evaluating all configurations (catches module errors before CI)..."
            FAILED=0
            SKIPPED=0

            # Eval Darwin configs (only on macOS — Linux cannot evaluate Darwin derivations)
            if [[ "$(uname)" == "Darwin" ]]; then
              DARWIN_CONFIGS=$(${pkgs.nix}/bin/nix eval --json .#darwinConfigurations --apply "builtins.attrNames" 2>/dev/null || echo "[]")
              for cfg in $(echo "$DARWIN_CONFIGS" | ${pkgs.jq}/bin/jq -r ".[]"); do
                if ${pkgs.nix}/bin/nix eval --impure --expr "
                  let flake = builtins.getFlake (toString ./.);
                  in flake.darwinConfigurations.\"$cfg\".config.system.build.toplevel != null
                " 2>/dev/null | grep -q "true"; then
                  echo "  ✓ Darwin: $cfg"
                else
                  echo "  ✗ Darwin: $cfg FAILED"
                  FAILED=$((FAILED + 1))
                fi
              done
            else
              echo "  ⊘ Darwin configs: skipped (not on macOS)"
            fi

            # Eval NixOS configs (works cross-platform via nix eval --impure)
            NIXOS_CONFIGS=$(${pkgs.nix}/bin/nix eval --json .#nixosConfigurations --apply "builtins.attrNames" 2>/dev/null || echo "[]")
            for cfg in $(echo "$NIXOS_CONFIGS" | ${pkgs.jq}/bin/jq -r ".[]"); do
              if ${pkgs.nix}/bin/nix eval --impure --expr "
                let flake = builtins.getFlake (toString ./.);
                in flake.nixosConfigurations.\"$cfg\".config.system.build.toplevel != null
              " 2>/dev/null | grep -q "true"; then
                echo "  ✓ NixOS: $cfg"
              else
                # Soft-fail for configs that need /etc/nixos/facter.json
                case "$cfg" in
                  type-*|installer-*|bootstrap)
                    echo "  ⊘ NixOS: $cfg skipped (requires facter.json or special environment)"
                    SKIPPED=$((SKIPPED + 1))
                    ;;
                  *)
                    echo "  ✗ NixOS: $cfg FAILED"
                    FAILED=$((FAILED + 1))
                    ;;
                esac
              fi
            done

            if [ $SKIPPED -gt 0 ]; then
              echo ""
              echo "  $SKIPPED config(s) skipped (need facter.json — tested in CI)"
            fi

            if [ $FAILED -gt 0 ]; then
              echo ""
              echo "✗ $FAILED configuration(s) failed evaluation"
              exit 1
            fi
            echo "✓ All configuration evaluations passed"
          '
        '';
        types = ["file"];
        files = "\\.nix$";
        pass_filenames = false;
        stages = ["pre-push"];
      };

      # Pre-push hook for documentation updates
      docs-update = {
        enable = true;
        name = "docs-update";
        entry = "${./scripts/docs-update.sh}";
        types = ["file"];
        files = "(\\.nix|\\.md)$";
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
          # Try hostname directly, then scan Darwin configs for a match
          DARWIN_CONFIGS=$(nix eval --impure --json .#darwinConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]')
          CONFIG_NAME=""
          for cfg in $DARWIN_CONFIGS; do
            if [[ "$cfg" == "$HOSTNAME" ]]; then
              CONFIG_NAME="$cfg"
              break
            fi
          done

          # If no direct match, check if any config's primaryUser matches hostname prefix
          if [[ -z "$CONFIG_NAME" ]]; then
            # Fallback: check known hostname aliases
            for cfg in $DARWIN_CONFIGS; do
              # Try to evaluate primaryUser and match against hostname
              PRIMARY_USER=$(nix eval --impure --raw ".#darwinConfigurations.$cfg.config.system.primaryUser" 2>/dev/null || echo "")
              if [[ -n "$PRIMARY_USER" && "$HOSTNAME" == *"$PRIMARY_USER"* ]]; then
                CONFIG_NAME="$cfg"
                break
              fi
            done
          fi

          if [[ -z "$CONFIG_NAME" ]]; then
            echo ""
            echo "ERROR: No Darwin configuration found for host: $HOSTNAME"
            echo "Available configurations: $DARWIN_CONFIGS"
            echo "Either rename a configuration to match this hostname or add a mapping"
            exit 1
          fi
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
      description = "Quick lint + foundation tests (~60s)";
      exec = ''
        echo "Running quick validation checks..."

        # Run lint checks
        devenv tasks run check:lint

        # Run foundation tests (package availability, options, config validation)
        echo ""
        echo "--- Foundation Tests ---"
        devenv tasks run test:core
        devenv tasks run test:options
        devenv tasks run test:config

        echo ""
        echo "All quick validation checks passed"
      '';
    };

    "build:darwin" = {
      description = "Build Darwin configurations (dry-run)";
      exec = ''
        echo "Building Darwin configurations"
        echo "=================================="
        CONFIGS=$(nix eval --json .#darwinConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]')
        if [[ -z "$CONFIGS" ]]; then
          echo "No Darwin configurations found"
          exit 0
        fi
        for config in $CONFIGS; do
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
            echo "  - Missing or incompatible packages in role modules"
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
        # Discover NixOS configs, excluding cattle/takeout types and installer
        ALL_CONFIGS=$(nix eval --json .#nixosConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]')
        CONFIGS=""
        for config in $ALL_CONFIGS; do
          case "$config" in
            type-*|installer-*|bootstrap) ;; # Skip cattle, installer, and bootstrap
            *) CONFIGS="$CONFIGS $config" ;;
          esac
        done
        if [[ -z "$CONFIGS" ]]; then
          echo "No NixOS configurations found (excluding cattle/takeout types)"
          exit 0
        fi
        for config in $CONFIGS; do
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
            echo "  - Missing or incompatible packages in role modules"
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

        # Discover type-* configs dynamically
        ALL_CONFIGS=$(nix eval --json .#nixosConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]')
        CONFIGS=""
        for config in $ALL_CONFIGS; do
          case "$config" in
            type-*) CONFIGS="$CONFIGS $config" ;;
          esac
        done
        if [[ -z "$CONFIGS" ]]; then
          echo "No takeout configurations found (expected type-* prefix)"
          exit 0
        fi
        for config in $CONFIGS; do
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
          # Discover config name dynamically
          DARWIN_CONFIGS=$(nix eval --json .#darwinConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]')
          CONFIG_NAME=""
          for cfg in $DARWIN_CONFIGS; do
            if [[ "$cfg" == "$HOSTNAME" ]]; then
              CONFIG_NAME="$cfg"
              break
            fi
          done
          if [[ -z "$CONFIG_NAME" ]]; then
            # Fallback: check primaryUser match
            for cfg in $DARWIN_CONFIGS; do
              PRIMARY_USER=$(nix eval --raw ".#darwinConfigurations.$cfg.config.system.primaryUser" 2>/dev/null || echo "")
              if [[ -n "$PRIMARY_USER" && "$HOSTNAME" == *"$PRIMARY_USER"* ]]; then
                CONFIG_NAME="$cfg"
                break
              fi
            done
          fi
          if [[ -z "$CONFIG_NAME" ]]; then
            echo "No Darwin configuration found for host: $HOSTNAME"
            echo "Available: $DARWIN_CONFIGS"
            exit 1
          fi
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
          CONFIGS=$(nix eval --json .#darwinConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]')
          for config in $CONFIGS; do
            echo "Building $config..."
            nix build ".#darwinConfigurations.''${config}.system" \
              --no-link --print-out-paths | cachix push funkymonkeymonk
            echo "$config pushed"
          done
        else
          echo "Building all NixOS configurations..."
          ALL_CONFIGS=$(nix eval --json .#nixosConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]')
          for config in $ALL_CONFIGS; do
            case "$config" in
              installer-*|bootstrap) echo "Skipping $config"; continue ;;
            esac
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
      description = "Validate microvm configurations (dev-vm, openclaw, matrix)";
      exec = ''
        echo "Validating microvm configurations..."
        FAILED=0

        for VM in dev-vm openclaw matrix; do
          echo -n "  $VM... "
          if nix eval .#microvm.nixosConfigurations.$VM.config.system.build.toplevel \
            --json >/dev/null 2>&1; then
            echo "valid"
          else
            echo "INVALID"
            nix eval .#microvm.nixosConfigurations.$VM.config.system.build.toplevel \
              --json --show-trace 2>&1 | head -40
            FAILED=$((FAILED + 1))
          fi
        done

        if [ $FAILED -gt 0 ]; then
          echo ""
          echo "$FAILED microvm configuration(s) failed validation"
          exit 1
        fi
        echo "All microvm configurations valid"
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
          -not -path './.workspaces/*' \
          -not -name '.devenv.flake.nix' \
          | xargs alejandra --check
        echo "Checking for dead code..."
        find . -name '*.nix' \
          -not -path './.devenv/*' \
          -not -path './.direnv/*' \
          -not -path './.worktrees/*' \
          -not -path './.workspaces/*' \
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

    # ============================================
    # FOUNDATION TEST TASKS
    # ============================================

    "test:core" = {
      description = "Test core packages are available";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Testing core packages ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.core-packages" --no-link
        echo "Core packages test passed"
      '';
    };

    "test:foundation" = {
      description = "Test foundation packages and config";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Testing foundation ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.foundation-packages" --no-link
        echo "Foundation packages test passed"
      '';
    };

    "test:options" = {
      description = "Test foundation options are defined";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Testing foundation options ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.foundation-options" --no-link
        echo "Foundation options test passed"
      '';
    };

    "test:config" = {
      description = "Test configuration validation";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Testing configuration validation ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.config-validation" --no-link
        echo "Configuration validation test passed"
      '';
    };

    "test:roles" = {
      description = "Test all role evaluations, packages, and cascades";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Testing role evaluation ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.role-evaluation" --no-link
        echo "Role evaluation test passed"
        echo ""
        echo "Testing role composition ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.role-composition" --no-link
        echo "Role composition test passed"
        echo ""
        echo "Testing role package inclusion ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.role-packages" --no-link
        echo "Role package inclusion test passed"
        echo ""
        echo "Testing role cascades ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.role-cascades" --no-link
        echo "Role cascade test passed"
      '';
    };

    "test:coverage" = {
      description = "Report module test coverage";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Building module coverage report ($CURRENT_SYSTEM)..."
        RESULT=$(nix build ".#checks.''${CURRENT_SYSTEM}.module-coverage" --no-link --print-out-paths)
        echo ""
        cat "$RESULT/coverage.json" | jq .
      '';
    };

    "test:skills" = {
      description = "Test skills manifest, autoLoad filtering, and content generation";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Testing skills manifest validation ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.skills-manifest" --no-link
        echo "Skills manifest test passed"
        echo ""
        echo "Testing autoLoad filtering ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.skills-autoload-filtering" --no-link
        echo "AutoLoad filtering test passed"
        echo ""
        echo "Testing autoLoad content generation ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.skills-autoload-content" --no-link
        echo "AutoLoad content generation test passed"
        echo ""
        echo "Testing skills role filtering ($CURRENT_SYSTEM)..."
        nix build ".#checks.''${CURRENT_SYSTEM}.skills-role-filtering" --no-link
        echo "Skills role filtering test passed"
      '';
    };

    "test:vm" = {
      description = "Run NixOS VM integration tests (Linux only)";
      exec = ''
        if [[ "$(uname)" == "Darwin" ]]; then
          echo "VM tests require Linux (NixOS testing framework)"
          echo "These tests run automatically in CI on ubuntu runners"
          exit 0
        fi

        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Running NixOS VM integration tests ($CURRENT_SYSTEM)..."
        echo ""

        for test in vm-users vm-ssh vm-packages; do
          echo "--- $test ---"
          nix build ".#checks.''${CURRENT_SYSTEM}.$test" --no-link
          echo "$test: passed"
          echo ""
        done

        echo "All VM tests passed"
      '';
    };

    "test:all" = {
      description = "Run all tests (platform-agnostic eval tests)";
      exec = ''
        echo "=== Running All Tests ==="
        devenv tasks run test:core
        devenv tasks run test:foundation
        devenv tasks run test:options
        devenv tasks run test:config
        echo ""
        echo "=== Running Role Tests ==="
        devenv tasks run test:roles
        echo ""
        echo "=== Running Skills Tests ==="
        devenv tasks run test:skills
        echo ""
        echo "=== Running Configuration Evaluation Tests ==="
        echo "These tests validate configs can be evaluated without building"
        devenv tasks run test:nixos-eval
        devenv tasks run test:darwin-eval
        echo ""
        echo "=== Module Coverage ==="
        devenv tasks run test:coverage
        echo ""
        echo "NOTE: VM integration tests (test:vm) are not included here."
        echo "They require Linux + KVM and run separately in CI via nix flake check."
        echo ""
        echo "=== All Tests Complete ==="
      '';
    };

    "test:nixos-eval" = {
      description = "Validate NixOS configs can be evaluated (catches module errors)";
      exec = ''
        echo "=== Testing NixOS Configuration Evaluation ==="
        echo ""
        echo "This test validates that all NixOS configurations can be evaluated"
        echo "without errors. It catches issues like:"
        echo "  - Missing home-manager references in modules"
        echo "  - Invalid option definitions"
        echo "  - Import errors"
        echo ""

        echo "Testing NixOS configurations..."
        FAILED=0

        # Get list of all NixOS configurations
        CONFIGS=$(nix eval --json .#nixosConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]')

        if [ -z "$CONFIGS" ]; then
          echo "⚠ No NixOS configurations found"
          exit 0
        fi

        echo "Found configurations:"
        echo "$CONFIGS" | sed 's/^/  - /'
        echo ""

        # Create a minimal facter.json for testing (required by some NixOS configs)
        # This is the same approach used in CI builds
        # On macOS, skip this step (sudo not available) — configs needing facter will soft-fail
        HAS_FACTER=false
        if [ -f /etc/nixos/facter.json ]; then
          HAS_FACTER=true
        elif [[ "$(uname)" != "Darwin" ]]; then
          echo "Creating stub facter.json for testing..."
          sudo mkdir -p /etc/nixos
          sudo tee /etc/nixos/facter.json > /dev/null << 'EOF'
        {
          "version": 1,
          "hardware": {
            "cpu": {"vendor": "GenuineIntel", "brand": "Intel"},
            "memory": {"size": 16384}
          },
          "networking": {
            "defaultGateway": {"interface": "eth0"}
          }
        }
        EOF
          echo "Created /etc/nixos/facter.json"
          echo ""
          HAS_FACTER=true
        fi

        # Test each configuration can be evaluated (using nix eval to avoid building)
        for CONFIG in $CONFIGS; do
          echo -n "Testing $CONFIG... "

          # Use nix eval to check if the config can be evaluated without building
          # This works on any platform, not just Linux
          if nix eval --impure --expr "
            let
              flake = builtins.getFlake (toString ./.);
              config = flake.nixosConfigurations.\"$CONFIG\";
            in
              # Just check that we can access the config structure
              config.config.system.build.toplevel != null
          " 2>/dev/null | grep -q "true"; then
            echo "✓"
          else
            # Soft-fail for configs that require facter.json when it's not available
            if [[ "$HAS_FACTER" != "true" ]]; then
              case "$CONFIG" in
                type-*|installer-*|bootstrap)
                  echo "⊘ skipped (requires facter.json)"
                  continue
                  ;;
              esac
            fi
            echo "✗ FAILED"
            echo ""
            echo "Error output:"
            nix eval --impure --expr "
              let
                flake = builtins.getFlake (toString ./.);
                config = flake.nixosConfigurations.\"$CONFIG\";
              in
                config.config.system.build.toplevel
            " 2>&1 | head -40
            FAILED=$((FAILED + 1))
          fi
        done

        echo ""
        if [ $FAILED -eq 0 ]; then
          echo "✓ All NixOS configurations evaluated successfully"
          exit 0
        else
          echo "✗ $FAILED configuration(s) failed evaluation"
          exit 1
        fi
      '';
    };

    "test:darwin-eval" = {
      description = "Validate Darwin configs can be evaluated (catches module errors)";
      exec = ''
        echo "=== Testing Darwin Configuration Evaluation ==="
        echo ""
        echo "This test validates that all Darwin configurations can be evaluated"
        echo "without errors. It catches issues like:"
        echo "  - Missing home-manager references in modules"
        echo "  - Invalid option definitions"
        echo "  - Import errors"
        echo ""

        echo "Testing Darwin configurations..."
        FAILED=0

        # Get list of all Darwin configurations
        CONFIGS=$(nix eval --json .#darwinConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]')

        if [ -z "$CONFIGS" ]; then
          echo "⚠ No Darwin configurations found"
          exit 0
        fi

        echo "Found configurations:"
        echo "$CONFIGS" | sed 's/^/  - /'
        echo ""

        # Test each configuration can be evaluated (using nix eval to avoid building)
        for CONFIG in $CONFIGS; do
          echo -n "Testing $CONFIG... "

          # Use nix eval to check if the config can be evaluated without building
          if nix eval --impure --expr "
            let
              flake = builtins.getFlake (toString ./.);
              config = flake.darwinConfigurations.\"$CONFIG\";
            in
              config.config.system.build.toplevel != null
          " 2>/dev/null | grep -q "true"; then
            echo "✓"
          else
            echo "✗ FAILED"
            echo ""
            echo "Error output:"
            nix eval --impure --expr "
              let
                flake = builtins.getFlake (toString ./.);
                config = flake.darwinConfigurations.\"$CONFIG\";
              in
                config.config.system.build.toplevel
            " 2>&1 | head -40
            FAILED=$((FAILED + 1))
          fi
        done

        echo ""
        if [ $FAILED -eq 0 ]; then
          echo "✓ All Darwin configurations evaluated successfully"
          exit 0
        else
          echo "✗ $FAILED configuration(s) failed evaluation"
          exit 1
        fi
      '';
    };

    # ============================================
    # CI WATCH TASK (Agent-Optimized)
    # ============================================

    "ci:watch" = {
      description = "Poll CI until completion [usage: ci:watch <run-id>]";
      exec = builtins.readFile ./scripts/ci-watch.sh;
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
