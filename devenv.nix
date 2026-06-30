{pkgs, ...}: let
  foundationPkgs = import ./modules/roles/foundation-packages.nix {inherit pkgs;};
in {
  packages =
    foundationPkgs.common
    ++ [
      # Nix development tools
      pkgs.alejandra
      pkgs.statix
      pkgs.deadnix
      pkgs.nix-tree
      pkgs.nvd
      pkgs.nixd
      pkgs.optnix
      pkgs.nix-unit

      # Linting and formatting
      pkgs.yamllint
      pkgs.yamlfmt
      pkgs.shellcheck

      # CI and deployment
      pkgs.cachix
      pkgs.deploy-rs

      # GitHub tools
      pkgs.gh-dash

      # Utility
      pkgs.rsync
      pkgs.sshpass

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
    alias agentsudo='op read "op://Private/$(hostname -s) Sudo Password/password" | sudo -S '

    # ============================================
    # JJ Workspace Support - Check if in workspace
    # ============================================
    # Source shared workspace detection library
    source ./modules/common/scripts/jj-workspace-lib

    # Check if we're in a jj workspace
    if command -v jj &>/dev/null; then
      _JJ_WORKSPACE_ROOT=$(jj root 2>/dev/null || pwd)
      _JJ_REPO_ROOT=$(detect_jj_repo_root "$_JJ_WORKSPACE_ROOT" || echo "$_JJ_WORKSPACE_ROOT")

      if is_jj_workspace "$_JJ_WORKSPACE_ROOT" "$_JJ_REPO_ROOT"; then
        # In workspace - create functions that run from repo root
        echo "📁 JJ Workspace: $(basename "$_JJ_WORKSPACE_ROOT")"
        echo "   Switch will run from: $_JJ_REPO_ROOT"
        echo ""

        # Use functions instead of aliases for better compatibility
        s() { (cd "$_JJ_REPO_ROOT" && devenv tasks run system:switch "$@"); }
        switch() { (cd "$_JJ_REPO_ROOT" && devenv tasks run system:switch "$@"); }
      else
        # In main repo - use normal functions
        s() { devenv tasks run system:switch "$@"; }
        switch() { devenv tasks run system:switch "$@"; }
      fi
    else
      # No jj - use normal functions
      s() { devenv tasks run system:switch "$@"; }
      switch() { devenv tasks run system:switch "$@"; }
    fi

    # Cleanup temp variables
    unset _JJ_WORKSPACE_ROOT _JJ_REPO_ROOT 2>/dev/null || true

    # Source switch-nix function (same source as system-wide install)
    source ./modules/common/scripts/switch-nix

    # Source interactive TUI functions (use these instead of devenv tasks)
    source ./modules/common/scripts/dev-ide
    source ./modules/common/scripts/pr-review
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
        stages = ["pre-commit" "pre-push"];
      };
      statix = {
        enable = true;
        stages = ["pre-commit" "pre-push"];
      };
      deadnix = {
        enable = true;
        entry = "${pkgs.deadnix}/bin/deadnix --no-underscore";
        stages = ["pre-commit" "pre-push"];
      };
      yamllint = {
        enable = true;
        stages = ["pre-commit" "pre-push"];
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
          # Check if config defines a custom sudoPasswordRef, otherwise use default pattern
          CUSTOM_REF=$(nix eval --impure --raw ".#darwinConfigurations.$CONFIG_NAME.config.myConfig.onepassword.sudoPasswordRef" 2>/dev/null || echo "")
          if [[ -n "$CUSTOM_REF" ]]; then
            PASSWORD_PATH="$CUSTOM_REF"
          else
            PASSWORD_PATH="op://Private/''${HOSTNAME} Sudo Password/password"
          fi
          echo "Fetching sudo password from 1Password..."
          echo "  Path: $PASSWORD_PATH"

          SUDO_PASSWORD=$(op read "$PASSWORD_PATH" 2>&1) || {
            echo ""
            echo "ERROR: Failed to read sudo password from 1Password"
            echo "  Attempted path: $PASSWORD_PATH"
            echo ""
            echo "Ensure the item exists in 1Password."
            echo "You can set myConfig.onepassword.sudoPasswordRef in the machine config"
            echo "to override the default path (op://Private/<hostname> Sudo Password/password)."
            exit 1
          }
          echo "Sudo password: retrieved"
          echo ""

          # Build and switch with output logging
          SWITCH_LOG="/tmp/system-switch-$(date +%Y%m%d-%H%M%S).log"
          echo "Build log: $SWITCH_LOG"
          echo ""

          set -o pipefail
          echo "$SUDO_PASSWORD" | sudo -S NIXPKGS_ALLOW_UNFREE=1 darwin-rebuild switch \
            --flake "./#$CONFIG_NAME" \
            --impure \
            --show-trace 2>&1 | tee "$SWITCH_LOG" || {
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

    "validate:disko" = {
      description = "Validate disko disk configurations";
      exec = ''
        echo "Validating Disko configurations"
        echo "================================="

        for config in single-disk-ext4; do
          echo "Checking disk-configs/$config.nix..."
          # Use nix build --dry-run to validate disko config without triggering
          # type-system recursion that can cause stack overflow with newer nixpkgs
          if nix build .#nixosConfigurations.zero.config.system.build.diskoScript \
              --no-link --dry-run --quiet 2>/dev/null; then
            echo "  disk-configs/$config.nix: valid"
          else
            echo "  disk-configs/$config.nix: INVALID"
            echo ""
            echo "Running build with verbose output:"
            nix build .#nixosConfigurations.zero.config.system.build.diskoScript \
              --no-link --dry-run --show-trace
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
    # MAINTENANCE TASKS
    # ============================================

    "flake:update" = {
      description = "Update the nix flake to latest versions";
      exec = "nix flake update";
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
        statix check . || true
        echo "Checking YAML files..."
        yamllint .
        echo "Checking jj-autosync shell scripts with shellcheck..."
        find ./modules/home-manager -name 'jj-autosync*.sh' -o -name 'jj-workspace-session.sh' -o -name 'jj-fast-sync.sh' \
          | xargs ${pkgs.shellcheck}/bin/shellcheck
        echo "Lint checks complete"
      '';
    };

    "test:eval" = {
      description = "Evaluate all NixOS and Darwin configurations (gates builds)";
      exec = ''
        echo "=== Configuration Evaluation ==="
        echo ""

        HAS_FACTER=false
        if [ -f /etc/nixos/facter.json ]; then
          HAS_FACTER=true
        elif sudo -n mkdir -p /etc/nixos 2>/dev/null; then
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
          HAS_FACTER=true
        fi

        echo "Evaluating NixOS configurations..."
        NIXOS_RESULTS=$(nix eval --impure --json --expr '
          let
            flake = builtins.getFlake (toString ./.);
            names = builtins.attrNames flake.nixosConfigurations;
            tryConfig = name: {
              inherit name;
              success = (builtins.tryEval (flake.nixosConfigurations.''${name}.config.system.build.toplevel != null)).success;
            };
          in
            map tryConfig names
        ' 2>/dev/null)

        NIXOS_FAILED=0
        NIXOS_SKIPPED=0
        if [ -n "$NIXOS_RESULTS" ]; then
          while IFS=: read -r name success; do
            if [ "$success" = "true" ]; then
              echo "  $name ✓"
            elif [[ "$HAS_FACTER" != "true" ]]; then
              case "$name" in
                type-*|installer-*|bootstrap)
                  echo "  $name ⊘ skipped"
                  NIXOS_SKIPPED=$((NIXOS_SKIPPED + 1)) ;;
                *)
                  echo "  $name ✗"
                  NIXOS_FAILED=$((NIXOS_FAILED + 1)) ;;
              esac
            else
              echo "  $name ✗"
              NIXOS_FAILED=$((NIXOS_FAILED + 1))
            fi
          done < <(echo "$NIXOS_RESULTS" | jq -r '.[] | "\(.name):\(.success)"')
        fi

        echo ""
        echo "Evaluating Darwin configurations..."
        DARWIN_RESULTS=$(nix eval --impure --json --expr '
          let
            flake = builtins.getFlake (toString ./.);
            names = builtins.attrNames flake.darwinConfigurations;
            tryConfig = name: {
              inherit name;
              success = (builtins.tryEval (flake.darwinConfigurations.''${name}.config.system.build.toplevel != null)).success;
            };
          in
            map tryConfig names
        ' 2>/dev/null)

        DARWIN_FAILED=0
        if [ -n "$DARWIN_RESULTS" ]; then
          while IFS=: read -r name success; do
            if [ "$success" = "true" ]; then echo "  $name ✓"
            else echo "  $name ✗"; DARWIN_FAILED=$((DARWIN_FAILED + 1)); fi
          done < <(echo "$DARWIN_RESULTS" | jq -r '.[] | "\(.name):\(.success)"')
        fi

        if [ $NIXOS_FAILED -gt 0 ] || [ $DARWIN_FAILED -gt 0 ]; then
          echo ""
          echo "✗ $NIXOS_FAILED NixOS + $DARWIN_FAILED Darwin config(s) failed evaluation"
          exit 1
        fi
        echo ""
        echo "✓ All configurations evaluated successfully"
      '';
    };

    "test:sketchybar" = {
      description = "Test sketchybar options, theme, and color conversion";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Running sketchybar tests ($CURRENT_SYSTEM)..."
        for test in sketchybar-options sketchybar-custom-options sketchybar-theme sketchybar-color-conversion sketchybar-platform-guard; do
          echo "--- $test ---"
          nix build ".#checks.''${CURRENT_SYSTEM}.$test" --no-link
          echo "$test: passed"
          echo ""
        done
        echo "All sketchybar tests passed"
      '';
    };

    "test:onepassword" = {
      description = "Test 1Password options, guard, and config output";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Running 1Password tests ($CURRENT_SYSTEM)..."
        for test in onepassword-guard onepassword-config-output; do
          echo "--- $test ---"
          nix build ".#checks.''${CURRENT_SYSTEM}.$test" --no-link
          echo "$test: passed"
          echo ""
        done
        echo "All 1Password tests passed"
      '';
    };

    "test:stack" = {
      description = "Test LLM stack integration (eval + runtime)";
      exec = ''
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "Running LLM stack eval test..."
        nix build ".#checks.''${CURRENT_SYSTEM}.stack-integration" --no-link
        echo "Eval test passed"
        echo ""
        echo "Running runtime integration test..."
        echo "(requires live system with all services running)"
        echo ""
        ./tests/test-stack-integration.sh
      '';
    };

    "test:all" = {
      description = "Run all tests (eval gates build, optimized for parallel CI)";
      exec = ''
        echo "=== Phase 1: Evaluation Checks ==="
        echo "Eval checks gate the build. Build runs only if all pass."
        echo ""

        devenv tasks run test:eval
        EVAL_RESULT=$?

        if [ $EVAL_RESULT -ne 0 ]; then
          echo ""
          echo "=== Eval Results: FAILED ==="
          echo ""
          echo "Skipping build - eval failures must be fixed first."
          exit 1
        fi

        echo ""
        echo "All evaluation checks passed."

        echo ""
        echo "=== Phase 2: Build Checks (single flake evaluation) ==="
        CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
        echo "System: $CURRENT_SYSTEM"
        echo ""
        echo "Building all check targets in one nix build to avoid repeated flake evaluation."
        echo ""

        nix build \
          ".#checks.''${CURRENT_SYSTEM}.core-packages" \
          ".#checks.''${CURRENT_SYSTEM}.foundation-packages" \
          ".#checks.''${CURRENT_SYSTEM}.foundation-options" \
          ".#checks.''${CURRENT_SYSTEM}.config-validation" \
          ".#checks.''${CURRENT_SYSTEM}.all-role-tests" \
          ".#checks.''${CURRENT_SYSTEM}.zsh-enable-single-location" \
          ".#checks.''${CURRENT_SYSTEM}.skills-manifest" \
          ".#checks.''${CURRENT_SYSTEM}.skills-autoload-filtering" \
          ".#checks.''${CURRENT_SYSTEM}.skills-autoload-content" \
          ".#checks.''${CURRENT_SYSTEM}.skills-role-filtering" \
          ".#checks.''${CURRENT_SYSTEM}.skills-external-identification" \
          ".#checks.''${CURRENT_SYSTEM}.skills-external-command-generation" \
          ".#checks.''${CURRENT_SYSTEM}.skills-external-empty-case" \
          ".#checks.''${CURRENT_SYSTEM}.email-agent-options" \
          ".#checks.''${CURRENT_SYSTEM}.email-backup-options" \
          ".#checks.''${CURRENT_SYSTEM}.email-custom-options" \
          ".#checks.''${CURRENT_SYSTEM}.email-composition" \
          ".#checks.''${CURRENT_SYSTEM}.email-backup-scripts" \
          ".#checks.''${CURRENT_SYSTEM}.email-separation" \
          ".#checks.''${CURRENT_SYSTEM}.sketchybar-options" \
          ".#checks.''${CURRENT_SYSTEM}.sketchybar-custom-options" \
          ".#checks.''${CURRENT_SYSTEM}.sketchybar-theme" \
          ".#checks.''${CURRENT_SYSTEM}.sketchybar-color-conversion" \
          ".#checks.''${CURRENT_SYSTEM}.sketchybar-platform-guard" \
          ".#checks.''${CURRENT_SYSTEM}.sketchybar-entrypoint" \
          ".#checks.''${CURRENT_SYSTEM}.onepassword-guard" \
          ".#checks.''${CURRENT_SYSTEM}.onepassword-config-output" \
          ".#checks.''${CURRENT_SYSTEM}.vane-options" \
          ".#checks.''${CURRENT_SYSTEM}.vane-custom-options" \
          ".#checks.''${CURRENT_SYSTEM}.openclaw-options" \
          ".#checks.''${CURRENT_SYSTEM}.vane-opnix-url-options" \
          ".#checks.''${CURRENT_SYSTEM}.jj-autosync-options" \
          ".#checks.''${CURRENT_SYSTEM}.jj-autosync-custom-options" \
          ".#checks.''${CURRENT_SYSTEM}.opencode-options" \
          ".#checks.''${CURRENT_SYSTEM}.opencode-custom-options" \
          ".#checks.''${CURRENT_SYSTEM}.opencode-provider-opnix-url" \
          ".#checks.''${CURRENT_SYSTEM}.shell-aliases" \
          ".#checks.''${CURRENT_SYSTEM}.fjj-options" \
          ".#checks.''${CURRENT_SYSTEM}.fjj-custom-options" \
          ".#checks.''${CURRENT_SYSTEM}.aerospace-options" \
          ".#checks.''${CURRENT_SYSTEM}.aerospace-custom-options" \
          ".#checks.''${CURRENT_SYSTEM}.workspace-switch" \
          ".#checks.''${CURRENT_SYSTEM}.llm-client-opencode" \
          ".#checks.''${CURRENT_SYSTEM}.llm-client-claude" \
          ".#checks.''${CURRENT_SYSTEM}.llm-client-pi" \
          ".#checks.''${CURRENT_SYSTEM}.llm-client-custom-host" \
          ".#checks.''${CURRENT_SYSTEM}.llm-client-no-ai-roles" \
          ".#checks.''${CURRENT_SYSTEM}.typed-attrs-options" \
          ".#checks.''${CURRENT_SYSTEM}.module-coverage" \
          --no-link --keep-going --print-build-logs
        BUILD_RESULT=$?

        echo ""
        echo "NOTE: VM integration tests (test:vm) are not included here."
        echo "They require Linux + KVM and run separately in CI via nix flake check."
        echo ""

        echo "=== Final Results ==="
        if [ $BUILD_RESULT -eq 0 ]; then
          echo "All tests passed"
          exit 0
        else
          echo "Build checks: FAILED"
          exit 1
        fi
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

        # Create a minimal facter.json for testing (required by some NixOS configs)
        # This is the same approach used in CI builds
        # On macOS, skip this step (sudo not available) — configs needing facter will soft-fail
        HAS_FACTER=false
        if [ -f /etc/nixos/facter.json ]; then
          HAS_FACTER=true
        elif sudo -n mkdir -p /etc/nixos 2>/dev/null; then
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
          HAS_FACTER=true
        fi

        echo "Evaluating NixOS configurations..."
        NIXOS_RESULTS=$(nix eval --impure --json --expr '
          let
            flake = builtins.getFlake (toString ./.);
            names = builtins.attrNames flake.nixosConfigurations;
            tryConfig = name: {
              inherit name;
              success = (builtins.tryEval (flake.nixosConfigurations.''${name}.config.system.build.toplevel != null)).success;
            };
          in
            map tryConfig names
        ' 2>/dev/null)

        NIXOS_FAILED=0
        NIXOS_SKIPPED=0
        if [ -n "$NIXOS_RESULTS" ]; then
          while IFS=: read -r name success; do
            if [ "$success" = "true" ]; then
              echo "  $name ✓"
            elif [[ "$HAS_FACTER" != "true" ]]; then
              case "$name" in
                type-*|installer-*|bootstrap)
                  echo "  $name ⊘ skipped"
                  NIXOS_SKIPPED=$((NIXOS_SKIPPED + 1)) ;;
                *)
                  echo "  $name ✗"
                  NIXOS_FAILED=$((NIXOS_FAILED + 1)) ;;
              esac
            else
              echo "  $name ✗"
              NIXOS_FAILED=$((NIXOS_FAILED + 1))
            fi
          done < <(echo "$NIXOS_RESULTS" | jq -r '.[] | "\(.name):\(.success)"')
        fi

        echo ""
        echo "Evaluating Darwin configurations..."
        DARWIN_RESULTS=$(nix eval --impure --json --expr '
          let
            flake = builtins.getFlake (toString ./.);
            names = builtins.attrNames flake.darwinConfigurations;
            tryConfig = name: {
              inherit name;
              success = (builtins.tryEval (flake.darwinConfigurations.''${name}.config.system.build.toplevel != null)).success;
            };
          in
            map tryConfig names
        ' 2>/dev/null)

        DARWIN_FAILED=0
        if [ -n "$DARWIN_RESULTS" ]; then
          while IFS=: read -r name success; do
            if [ "$success" = "true" ]; then echo "  $name ✓"
            else echo "  $name ✗"; DARWIN_FAILED=$((DARWIN_FAILED + 1)); fi
          done < <(echo "$DARWIN_RESULTS" | jq -r '.[] | "\(.name):\(.success)"')
        fi

        if [ $NIXOS_FAILED -gt 0 ] || [ $DARWIN_FAILED -gt 0 ]; then
          echo ""
          echo "✗ $NIXOS_FAILED NixOS + $DARWIN_FAILED Darwin config(s) failed evaluation"
          exit 1
        fi
        echo ""
        echo "✓ All configurations evaluated successfully"
      '';
    };

    "test:checks" = {
      description = "Run nix-unit eval tests (fast, no derivation builds)";
      after = ["test:eval"];
      exec = ''
        echo "=== Running nix-unit tests ==="
        nix-unit ./tests/nix-unit-tests.nix
      '';
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
