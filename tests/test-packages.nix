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
        watchman
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
      EXPECTED_ROLES="foundation developer creative gaming desktop workstation entertainment agent-skills opencode claude pi llm-host microvm-host"
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
}
