# Package availability and configuration tests
# Tests verify packages are instantiable and modules evaluate correctly.
{pkgs, ...}: {
  # Test that core packages are actually instantiable
  # If any package fails to evaluate, this derivation fails
  corePackagesTest =
    pkgs.runCommand "test-core-packages"
    {
      nativeBuildInputs = with pkgs; [git curl wget coreutils vim];
    }
    ''
      echo "=== Testing Core Packages ==="

      # Verify each core package is on PATH (proving it was instantiated)
      for cmd in git curl wget vim; do
        if command -v "$cmd" > /dev/null 2>&1; then
          echo "  $cmd: found at $(command -v $cmd)"
        else
          echo "  $cmd: NOT FOUND"
          exit 1
        fi
      done

      echo "All core packages verified"
      touch $out
    '';

  # Test that foundation packages are instantiable
  # Including them in nativeBuildInputs forces Nix to evaluate each one
  foundationPackagesTest =
    pkgs.runCommand "test-foundation-packages"
    {
      nativeBuildInputs = with pkgs; [
        helix
        htop
        zellij
        jq
        _1password-cli
        gh
        jujutsu
        delta
        tree
        zoxide
        fzf
        ripgrep
        fd
        devenv
        direnv
        rclone
        bat
        jnv
        docker
        colima
        zinit
        zsh
        glow
        antigen
      ];
    }
    ''
      echo "=== Testing Foundation Packages ==="

      # Spot-check key foundation tools are on PATH
      for cmd in hx jq gh jj delta rg fd fzf zoxide bat devenv direnv zellij; do
        if command -v "$cmd" > /dev/null 2>&1; then
          echo "  $cmd: found"
        else
          echo "  $cmd: NOT FOUND"
          exit 1
        fi
      done

      echo "All foundation packages verified"
      touch $out
    '';

  # Test configuration structure by evaluating modules
  configValidationTest = let
    # Evaluate modules to verify they compose without errors
    testEval = pkgs.lib.evalModules {
      modules = [
        ../modules/common/options.nix
        ../modules/roles/default.nix
        {
          options.nixpkgs.hostPlatform = pkgs.lib.mkOption {
            type = pkgs.lib.types.anything;
            default = {inherit (pkgs.stdenv.hostPlatform) system;};
          };
          # Stub options that role modules may set
          options.environment = {
            systemPackages = pkgs.lib.mkOption {
              type = pkgs.lib.types.listOf pkgs.lib.types.package;
              default = [];
            };
            variables = pkgs.lib.mkOption {
              type = pkgs.lib.types.attrsOf pkgs.lib.types.str;
              default = {};
            };
            sessionVariables = pkgs.lib.mkOption {
              type = pkgs.lib.types.attrsOf pkgs.lib.types.str;
              default = {};
            };
            shellAliases = pkgs.lib.mkOption {
              type = pkgs.lib.types.attrsOf pkgs.lib.types.str;
              default = {};
            };
          };
          options.programs = pkgs.lib.mkOption {
            type = pkgs.lib.types.attrsOf pkgs.lib.types.anything;
            default = {};
          };
          options.homebrew = pkgs.lib.mkOption {
            type = pkgs.lib.types.anything;
            default = {};
          };
        }
        {
          config._module.args = {inherit pkgs;};
        }
      ];
    };
    inherit (testEval.config.myConfig) roles;
    roleNames = builtins.attrNames roles;
  in
    pkgs.runCommand "test-config-validation"
    {}
    ''
      echo "=== Testing Configuration Validation ==="

      # Verify all expected roles exist (evaluated at Nix level)
      ${pkgs.lib.concatMapStringsSep "\n" (name: ''echo "  Role '${name}': defined"'') roleNames}

      # Verify expected roles are present
      EXPECTED_ROLES="foundation developer creative gaming desktop workstation entertainment agent-skills opencode claude pi llm-host"
      ACTUAL_ROLES="${builtins.concatStringsSep " " roleNames}"

      for role in $EXPECTED_ROLES; do
        if echo "$ACTUAL_ROLES" | grep -qw "$role"; then
          echo "  Required role '$role': present"
        else
          echo "  Required role '$role': MISSING"
          exit 1
        fi
      done

      # Verify foundation defaults to enabled
      echo "  foundation.enable default: ${builtins.toJSON roles.foundation.enable}"
      ${
        if roles.foundation.enable
        then ''echo "  foundation defaults to enabled: OK"''
        else ''echo "  foundation should default to enabled!"; exit 1''
      }

      echo "Configuration structure valid"
      touch $out
    '';

  # Test foundation options by evaluating their types and defaults
  foundationOptionsTest = let
    testEval = pkgs.lib.evalModules {
      modules = [
        ../modules/common/options.nix
        {
          options.nixpkgs.hostPlatform = pkgs.lib.mkOption {
            type = pkgs.lib.types.anything;
            default = {inherit (pkgs.stdenv.hostPlatform) system;};
          };
        }
        {
          config._module.args = {inherit pkgs;};
        }
        {
          config.myConfig = {
            users = [
              {
                name = "testuser";
                email = "test@example.com";
                fullName = "Test User";
                isAdmin = true;
                sshIncludes = [];
              }
            ];
            development.enable = true;
            agent-skills.enable = false;
            onepassword.enable = false;
            opencode.enable = false;
          };
        }
      ];
    };
    evaluatedConfig = testEval.config.myConfig;
  in
    pkgs.runCommand "test-foundation-options"
    {}
    ''
      echo "=== Testing Foundation Options ==="

      # These strings are computed at Nix eval time from the actual module system.
      # If any option type is wrong, this derivation will fail to instantiate.
      echo "  users count: ${toString (builtins.length evaluatedConfig.users)}"
      echo "  first user name: ${(builtins.head evaluatedConfig.users).name}"
      echo "  development.enable: ${builtins.toJSON evaluatedConfig.development.enable}"
      echo "  isDarwin: ${builtins.toJSON evaluatedConfig.isDarwin}"
      echo "  ollama.enable: ${builtins.toJSON evaluatedConfig.ollama.enable}"
      echo "  ollama.port: ${toString evaluatedConfig.ollama.port}"
      echo "  opencode.enable: ${builtins.toJSON evaluatedConfig.opencode.enable}"
      echo "  zellij.enable: ${builtins.toJSON evaluatedConfig.zellij.enable}"

      # Verify role options exist
      echo "  roles.foundation.enable: ${builtins.toJSON evaluatedConfig.roles.foundation.enable}"
      echo "  roles.developer.enable: ${builtins.toJSON evaluatedConfig.roles.developer.enable}"

      echo "All foundation options verified"
      touch $out
    '';

  # Test onepassword module options including new opnix integration
  onepasswordOptionsTest = let
    testEval = pkgs.lib.evalModules {
      modules = [
        ../modules/common/options.nix
        {
          options.nixpkgs.hostPlatform = pkgs.lib.mkOption {
            type = pkgs.lib.types.anything;
            default = {inherit (pkgs.stdenv.hostPlatform) system;};
          };
        }
        {
          config._module.args = {inherit pkgs;};
        }
        {
          config.myConfig.onepassword = {
            enable = true;
            enableGUI = true;
            enableSSHAgent = true;
            enableGitSigning = true;
            signingKey = "ssh-ed25519 AAAAC3...";
            enableSudo = true;
            tokenFile = "/etc/custom/opnix-token";
            secrets = {
              testApiKey = {
                reference = "op://vault/item/credential";
                path = "/run/secrets/test-api-key";
                mode = "0600";
                owner = "testuser";
                group = "users";
                services = ["test-service"];
              };
            };
          };
        }
      ];
    };
    cfg = testEval.config.myConfig.onepassword;
  in
    pkgs.runCommand "test-onepassword-options"
    {}
    ''
      echo "=== Testing 1Password Options ==="

      # Verify basic options
      echo "  enable: ${builtins.toJSON cfg.enable}"
      echo "  enableGUI: ${builtins.toJSON cfg.enableGUI}"
      echo "  enableSSHAgent: ${builtins.toJSON cfg.enableSSHAgent}"
      echo "  enableGitSigning: ${builtins.toJSON cfg.enableGitSigning}"
      echo "  enableSudo: ${builtins.toJSON cfg.enableSudo}"

      # Verify new opnix options
      echo "  tokenFile: ${builtins.toJSON cfg.tokenFile}"
      echo "  secrets count: ${toString (builtins.length (builtins.attrNames cfg.secrets))}"

      # Verify secrets structure
      ${
        if cfg.secrets ? testApiKey
        then ''
          echo "  secrets.testApiKey.reference: ${builtins.toJSON cfg.secrets.testApiKey.reference}"
          echo "  secrets.testApiKey.path: ${builtins.toJSON cfg.secrets.testApiKey.path}"
          echo "  secrets.testApiKey.mode: ${builtins.toJSON cfg.secrets.testApiKey.mode}"
          echo "  secrets.testApiKey.owner: ${builtins.toJSON cfg.secrets.testApiKey.owner}"
          echo "  secrets.testApiKey.group: ${builtins.toJSON cfg.secrets.testApiKey.group}"
          echo "  secrets.testApiKey.services: ${builtins.toJSON cfg.secrets.testApiKey.services}"
        ''
        else ''echo "  ERROR: testApiKey secret not found"; exit 1''
      }

      # Verify default tokenFile path
      DEFAULT_TOKEN_FILE="/etc/opnix-token"
      ${
        if cfg.tokenFile == "/etc/custom/opnix-token"
        then ''echo "  Custom tokenFile path set: OK"''
        else ''echo "  ERROR: Custom tokenFile path not set correctly"; exit 1''
      }

      echo "All 1Password options verified"
      touch $out
    '';

  # Test onepassword.nix config output: hasOpnix guard
  # When opnix module is NOT available, services.onepassword-secrets should not be set
  onepasswordGuardTest = let
    # Evaluate WITHOUT opnix module (no services.onepassword-secrets option)
    testEvalNoOpnix = pkgs.lib.evalModules {
      modules = [
        ../modules/common/options.nix
        ../modules/common/onepassword.nix
        {
          options.nixpkgs.hostPlatform = pkgs.lib.mkOption {
            type = pkgs.lib.types.anything;
            default = {inherit (pkgs.stdenv.hostPlatform) system;};
          };
          options.environment.systemPackages = pkgs.lib.mkOption {
            type = pkgs.lib.types.listOf pkgs.lib.types.package;
            default = [];
          };
          # Stub programs._1password for NixOS path
          options.programs._1password = pkgs.lib.mkOption {
            type = pkgs.lib.types.anything;
            default = {};
          };
          # No services.onepassword-secrets option here — simulates no opnix
          options.services = pkgs.lib.mkOption {
            type = pkgs.lib.types.attrsOf pkgs.lib.types.anything;
            default = {};
          };
        }
        {
          config._module.args = {inherit pkgs;};
        }
        {
          config.myConfig.onepassword = {
            enable = true;
            secrets = {
              testKey = {
                reference = "op://vault/item/cred";
                path = "/run/secrets/test";
              };
            };
          };
        }
      ];
    };
    cfgNoOpnix = testEvalNoOpnix.config;
    # Check that no services.onepassword-secrets config is produced
    hasOpnixConfig = (cfgNoOpnix.services or {}) ? onepassword-secrets;
  in
    pkgs.runCommand "test-onepassword-guard"
    {}
    ''
      echo "=== Testing 1Password hasOpnix Guard ==="

      # Without opnix module, services.onepassword-secrets should NOT be configured
      ${
        if !hasOpnixConfig
        then ''echo "  No opnix config without module: OK"''
        else ''echo "  ERROR: opnix config present without module!"; exit 1''
      }

      # Verify the module evaluates without error (no infinite recursion)
      echo "  Module evaluates cleanly without opnix: OK"

      echo "1Password guard test passed"
      touch $out
    '';

  # Test onepassword.nix config output: platform-specific package installation
  # Note: isDarwin is read-only, computed from pkgs.stdenv.hostPlatform.system.
  # On Darwin hosts, we can only test the Darwin path. The NixOS path is verified
  # by CI running on Linux runners.
  onepasswordConfigOutputTest = let
    isDarwin = builtins.elem pkgs.stdenv.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"];

    # Evaluate onepassword.nix with stubs appropriate for the current platform
    testEval = pkgs.lib.evalModules {
      modules = [
        ../modules/common/options.nix
        ../modules/common/onepassword.nix
        {
          options.nixpkgs.hostPlatform = pkgs.lib.mkOption {
            type = pkgs.lib.types.anything;
            default = {inherit (pkgs.stdenv.hostPlatform) system;};
          };
          options.environment.systemPackages = pkgs.lib.mkOption {
            type = pkgs.lib.types.listOf pkgs.lib.types.package;
            default = [];
          };
          # Stub programs._1password for NixOS path
          options.programs._1password = {
            enable = pkgs.lib.mkOption {
              type = pkgs.lib.types.bool;
              default = false;
            };
            package = pkgs.lib.mkOption {
              type = pkgs.lib.types.package;
              default = pkgs._1password-cli;
            };
          };
          options.services = pkgs.lib.mkOption {
            type = pkgs.lib.types.attrsOf pkgs.lib.types.anything;
            default = {};
          };
        }
        {
          config._module.args = {inherit pkgs;};
        }
        {
          config.myConfig.onepassword.enable = true;
        }
      ];
    };
    evalCfg = testEval.config;
    pkgNames = map (p: p.name or p.pname or "unknown") evalCfg.environment.systemPackages;
    hasCli = builtins.any (n: pkgs.lib.hasInfix "1password" n) pkgNames;
  in
    pkgs.runCommand "test-onepassword-config-output"
    {}
    ''
      echo "=== Testing 1Password Config Output ==="
      echo "  Platform: ${
        if isDarwin
        then "Darwin"
        else "NixOS"
      }"

      ${
        if isDarwin
        then ''
          # On Darwin: should add _1password-cli to systemPackages
          ${
            if hasCli
            then ''echo "  Darwin: _1password-cli in systemPackages: OK"''
            else ''echo "  Darwin: _1password-cli NOT in systemPackages!"; exit 1''
          }

          # On Darwin: programs._1password should NOT be enabled (NixOS-only option)
          ${
            if !evalCfg.programs._1password.enable
            then ''echo "  Darwin: programs._1password.enable = false: OK (NixOS-only)"''
            else ''echo "  Darwin: programs._1password should not be enabled!"; exit 1''
          }
        ''
        else ''
          # On NixOS: should enable programs._1password
          ${
            if evalCfg.programs._1password.enable
            then ''echo "  NixOS: programs._1password.enable = true: OK"''
            else ''echo "  NixOS: programs._1password.enable should be true!"; exit 1''
          }

          # On NixOS: should NOT add CLI to systemPackages (handled by programs._1password)
          ${
            if !hasCli
            then ''echo "  NixOS: _1password-cli NOT in systemPackages: OK (handled by programs._1password)"''
            else ''echo "  NixOS: _1password-cli should not be in systemPackages!"; exit 1''
          }
        ''
      }

      echo "1Password config output test passed"
      touch $out
    '';

  # Test that programs.zsh.enable is set in exactly one location (shell.nix)
  # This is a structural test to prevent redundant duplicate assignments.
  zshEnableSingleLocationTest =
    pkgs.runCommand "test-zsh-enable-single-location"
    {
      src = ../.;
    }
    ''
      echo "=== Testing programs.zsh.enable single location ==="

      # Count occurrences across the three files that previously had duplicates
      foundation_count=$(grep -c "programs\.zsh\.enable" $src/modules/roles/foundation.nix || true)
      shell_count=$(grep -c "programs\.zsh\.enable" $src/modules/common/shell.nix || true)
      core_count=$(grep -c "programs\.zsh\.enable" $src/modules/common/core.nix || true)
      total=$((foundation_count + shell_count + core_count))

      echo "  modules/roles/foundation.nix:   $foundation_count occurrence(s)"
      echo "  modules/common/shell.nix:        $shell_count occurrence(s)"
      echo "  modules/common/core.nix:         $core_count occurrence(s)"
      echo "  Total across three files:        $total"

      # Canonical location must have the setting
      if [ "$shell_count" -ne 1 ]; then
        echo "  FAIL: modules/common/shell.nix should have exactly 1 occurrence (got $shell_count)"
        exit 1
      fi
      echo "  modules/common/shell.nix has exactly 1 occurrence: OK"

      # Duplicates must be absent
      if [ "$foundation_count" -ne 0 ]; then
        echo "  FAIL: modules/roles/foundation.nix should have 0 occurrences (got $foundation_count)"
        exit 1
      fi
      echo "  modules/roles/foundation.nix has 0 occurrences: OK"

      if [ "$core_count" -ne 0 ]; then
        echo "  FAIL: modules/common/core.nix should have 0 occurrences (got $core_count)"
        exit 1
      fi
      echo "  modules/common/core.nix has 0 occurrences: OK"

      echo "programs.zsh.enable single-location check passed"
      touch $out
    '';
}
