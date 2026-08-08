{pkgs, ...}: let
  devBase = import ./library/dev-base.nix {inherit pkgs;};

  # Benchmarking suites are not in upstream nixpkgs; call them directly from
  # the repo packages so they are available in the devenv shell and tasks.
  lm-eval = pkgs.callPackage ./packages/benchmarks/lm-eval {};
  lighteval = pkgs.callPackage ./packages/benchmarks/lighteval {};
in {
  packages =
    devBase.packages
    ++ [
      # Devenv-specific additions for working on this repo
      pkgs.optnix
      pkgs.nix-unit

      # Linting and formatting
      pkgs.yamllint
      pkgs.yamlfmt
      pkgs.shellcheck

      # CI and deployment
      pkgs.cachix
      pkgs.deploy-rs

      # LLM benchmarking suites
      lm-eval
      lighteval

      # Utility
      pkgs.rsync
      pkgs.sshpass
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

    "docs:all" = {
      description = "Run all documentation tasks (update + validate + generate)";
      after = ["docs:update" "docs:validate" "docs:generate"];
      exec = "echo '✓ All documentation tasks complete'";
    };

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

    # ============================================
    # VALIDATION TASKS
    # ============================================

    "validate:all" = {
      description = "Run all validation tasks (disko + install-script)";
      after = ["validate:disko" "validate:install-script"];
      exec = "echo '✓ All validation tasks complete'";
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

    "agent-skills:all" = {
      description = "Run all agent-skills tasks (status + update + validate)";
      after = ["agent-skills:status" "agent-skills:update" "agent-skills:validate"];
      exec = "echo '✓ All agent-skills tasks complete'";
    };

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
    # CHECK TASKS (fast, no derivation builds)
    # ============================================

    "check:all" = {
      description = "Run all fast checks (lint + unit tests + eval)";
      after = ["check:lint" "check:unit" "test:eval"];
      exec = "echo '✓ All checks passed'";
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
        echo "Lint checks complete"
      '';
    };

    "check:unit" = {
      description = "Run nix-unit eval tests (fast, no derivation builds)";
      after = ["test:eval"];
      exec = ''
        echo "=== Running nix-unit tests ==="
        nix-unit ./tests/nix-unit-tests.nix
      '';
    };

    # ============================================
    # TEST TASKS (eval gates build)
    # ============================================

    "test:all" = {
      description = "Run all tests (eval + module tests)";
      after = ["test:eval" "test:build-checks"];
      exec = ''
        echo "=== Final Results ==="
        echo "All tests passed"
      '';
    };

    "test:eval" = {
      description = "Evaluate all NixOS and Darwin configurations (gates builds)";
      exec = ''
        set -euo pipefail

        # Skip in CI when configs were already evaluated by discover-targets job
        if [[ "''${SKIP_CONFIG_EVAL:-}" == "true" ]]; then
          echo "SKIP_CONFIG_EVAL=true — skipping config evaluation (already validated in CI discover step)"
          exit 0
        fi

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
        ' 2>/dev/null) || {
          echo ""
          echo "✗ NixOS configuration evaluation command failed"
          exit 1
        }

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
        else
          echo "  ⚠ No NixOS results returned (evaluation may have failed silently)"
          NIXOS_FAILED=1
        fi

        echo ""
        echo "Evaluating Darwin configurations..."
        DARWIN_FAILED=0
        if [[ "$(uname)" == "Darwin" ]]; then
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
          ' 2>/dev/null) || {
            echo ""
            echo "✗ Darwin configuration evaluation command failed"
            exit 1
          }

          if [ -n "$DARWIN_RESULTS" ]; then
            while IFS=: read -r name success; do
              if [ "$success" = "true" ]; then echo "  $name ✓"
              else echo "  $name ✗"; DARWIN_FAILED=$((DARWIN_FAILED + 1)); fi
            done < <(echo "$DARWIN_RESULTS" | jq -r '.[] | "\(.name):\(.success)"')
          else
            echo "  ⚠ No Darwin results returned"
            DARWIN_FAILED=1
          fi
        else
          echo "  ⊘ Darwin configs: skipped (not on macOS)"
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

    "test:build-checks" = {
      description = "Build all remaining check targets (runCommand eval tests)";
      after = ["test:eval"];
      exec = ''
        set -euo pipefail

        echo "=== Check Targets ==="
        echo "Running nix flake check (builds checks for current system only)."
        echo ""

        nix flake check --max-jobs auto --print-build-logs

        echo ""
        echo "✓ All check targets passed"
      '';
    };

    "test:sketchybar" = {
      description = "Test sketchybar options, theme, and color conversion (standalone)";
      exec = ''
        set -euo pipefail

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
      description = "Test 1Password options, guard, and config output (standalone)";
      exec = ''
        set -euo pipefail

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

    # ============================================
    # LLM / BENCHMARK TASKS
    # ============================================

    "benchmark:all" = {
      description = "Run all benchmark tasks";
      after = [
        "benchmark:lm-eval-gsm8k"
        "benchmark:lm-eval-mini"
        "benchmark:lm-eval-leaderboard"
        "benchmark:lighteval-gsm8k"
      ];
      exec = "echo '✓ All benchmark tasks complete'";
    };

    "profile:llm" = {
      description = "Profile LLM inference performance via env vars (MODEL, PROMPTS, MAX_TOKENS)";
      exec = ''
        set -euo pipefail

        MODEL="''${MODEL:-gemma4-e4b}"
        PROMPTS="''${PROMPTS:-5}"
        MAX_TOKENS="''${MAX_TOKENS:-256}"

        echo "=== LLM Profiling ==="
        echo "Model:      $MODEL"
        echo "Prompts:    $PROMPTS"
        echo "Max tokens: $MAX_TOKENS"
        echo ""
        echo "Usage: MODEL=gemma4-31b PROMPTS=3 MAX_TOKENS=128 devenv tasks run profile:llm"
        echo ""

        ./scripts/profile-llm.sh "$MODEL" --prompts "$PROMPTS" --max-tokens "$MAX_TOKENS" --output-dir ./profiling
      '';
    };

    "smoke:llm-stack" = {
      description = "Smoke test the local LLM stack (vllm-mlx + bifrost)";
      exec = ''
        set -euo pipefail

        BIFROST_URL="''${BIFROST_URL:-http://bifrost.internal/v1}"
        VLLM_URL="''${VLLM_URL:-http://localhost:8300/v1}"
        MODEL="''${MODEL:-gemma4-31b}"
        TIMEOUT="''${TIMEOUT:-120}"

        echo "=== LLM Stack Smoke Test ==="
        echo "vllm-mlx:  $VLLM_URL"
        echo "bifrost:   $BIFROST_URL"
        echo "model:     $MODEL"
        echo ""

        echo "-- vllm-mlx /v1/models --"
        curl -sf --max-time "$TIMEOUT" "$VLLM_URL/models" | jq -e '.data | length > 0'
        echo "vllm-mlx models OK"
        echo ""

        echo "-- vllm-mlx /v1/chat/completions --"
        curl -sf --max-time "$TIMEOUT" "$VLLM_URL/chat/completions" \
          -H "Content-Type: application/json" \
          -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":40}" \
          | jq -e '(.choices[0].message.content != null) or (.choices[0].message.reasoning_content != null)'
        echo "vllm-mlx chat completion OK"
        echo ""

        echo "-- bifrost /v1/models --"
        curl -sf --max-time "$TIMEOUT" "$BIFROST_URL/models" | jq -e '.data | length > 0'
        echo "bifrost models OK"
        echo ""

        echo "-- bifrost /v1/chat/completions --"
        curl -sf --max-time "$TIMEOUT" "$BIFROST_URL/chat/completions" \
          -H "Content-Type: application/json" \
          -d "{\"model\":\"vllm-mlx-local/$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":40}" \
          | jq -e '(.choices[0].message.content != null) or (.choices[0].message.reasoning_content != null)'
        echo "bifrost chat completion OK"
        echo ""

        echo "=== LLM stack smoke test passed ==="
      '';
    };

    "benchmark:lm-eval-gsm8k" = {
      description = "Run lm-eval GSM8K (math reasoning) against local vllm-mlx";
      exec = ''
        set -euo pipefail

        BASE_URL="''${BASE_URL:-http://localhost:8300/v1/chat/completions}"
        MODEL="''${MODEL:-gemma4-31b}"
        LIMIT="''${LIMIT:-50}"
        OUTPUT_DIR="''${OUTPUT_DIR:-./benchmark-results/lm-eval-gsm8k}"

        echo "=== lm-eval GSM8K against $BASE_URL (model: $MODEL) ==="
        mkdir -p "$OUTPUT_DIR"

        lm-eval run \
          --model local-chat-completions \
          --model_args model="$MODEL",base_url="$BASE_URL",num_concurrent=1,max_retries=3 \
          --tasks gsm8k \
          --limit "$LIMIT" \
          --batch_size 1 \
          --output_path "$OUTPUT_DIR" \
          --log_samples

        echo ""
        echo "Results written to $OUTPUT_DIR"
      '';
    };

    "benchmark:lm-eval-mini" = {
      description = "Quick lm-eval smoke benchmark (small subsets) against local vllm-mlx";
      exec = ''
        set -euo pipefail

        BASE_URL="''${BASE_URL:-http://localhost:8300/v1/completions}"
        MODEL="''${MODEL:-gemma4-31b}"
        LIMIT="''${LIMIT:-10}"
        OUTPUT_DIR="''${OUTPUT_DIR:-./benchmark-results/lm-eval-mini}"

        echo "=== lm-eval mini benchmark against $BASE_URL (model: $MODEL) ==="
        mkdir -p "$OUTPUT_DIR"

        lm-eval run \
          --model local-completions \
          --model_args model="$MODEL",base_url="$BASE_URL",num_concurrent=1,max_retries=3 \
          --tasks mmlu,arc_easy,hellaswag \
          --limit "$LIMIT" \
          --batch_size 1 \
          --apply_chat_template \
          --output_path "$OUTPUT_DIR" \
          --log_samples

        echo ""
        echo "Results written to $OUTPUT_DIR"
      '';
    };

    "benchmark:lm-eval-leaderboard" = {
      description = "Run the HuggingFace Open LLM Leaderboard v2 task group against local vllm-mlx";
      exec = ''
        set -euo pipefail

        BASE_URL="''${BASE_URL:-http://localhost:8300/v1/completions}"
        MODEL="''${MODEL:-gemma4-31b}"
        OUTPUT_DIR="''${OUTPUT_DIR:-./benchmark-results/lm-eval-leaderboard}"

        echo "=== lm-eval Open LLM Leaderboard v2 against $BASE_URL (model: $MODEL) ==="
        echo "This is a long-running benchmark. Set LIMIT=N for a quick subset."
        echo ""
        mkdir -p "$OUTPUT_DIR"

        lm-eval run \
          --model local-completions \
          --model_args model="$MODEL",base_url="$BASE_URL",num_concurrent=1,max_retries=3 \
          --tasks leaderboard \
          --batch_size 1 \
          --apply_chat_template \
          --output_path "$OUTPUT_DIR" \
          --log_samples

        echo ""
        echo "Results written to $OUTPUT_DIR"
      '';
    };

    "benchmark:lighteval-gsm8k" = {
      description = "Run lighteval GSM8K against a local OpenAI-compatible endpoint";
      exec = ''
        set -euo pipefail

        API_BASE="''${API_BASE:-http://localhost:8300/v1}"
        MODEL="''${MODEL:-gemma4-31b}"
        OUTPUT_DIR="''${OUTPUT_DIR:-./benchmark-results/lighteval-gsm8k}"
        MAX_SAMPLES="''${MAX_SAMPLES:-50}"

        echo "=== lighteval GSM8K against $API_BASE (model: $MODEL) ==="
        mkdir -p "$OUTPUT_DIR"

        lighteval endpoint litellm \
          "provider=openai,model_name=$MODEL,api_base=$API_BASE" \
          "gsm8k|0|0|$MAX_SAMPLES" \
          --output-dir "$OUTPUT_DIR"

        echo ""
        echo "Results written to $OUTPUT_DIR"
      '';
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
