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

  # Test sketchybar module options by evaluating their types and custom values
  sketchybarOptionsTest = let
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
          config.myConfig.sketchybar = {
            enable = true;
            height = 50;
            padding = 4;
            groupPadding = 12;
            useAerospaceIntegration = false;
            extraConfig = "-- test config";
          };
        }
      ];
    };
    cfg = testEval.config.myConfig.sketchybar;
  in
    pkgs.runCommand "test-sketchybar-options"
    {}
    ''
      echo "=== Testing Sketchybar Options ==="

      # Verify option values are correctly set
      echo "  enable: ${builtins.toJSON cfg.enable}"
      echo "  height: ${toString cfg.height}"
      echo "  padding: ${toString cfg.padding}"
      echo "  groupPadding: ${toString cfg.groupPadding}"
      echo "  useAerospaceIntegration: ${builtins.toJSON cfg.useAerospaceIntegration}"

      # Verify custom values override defaults
      ${
        if cfg.height == 50
        then ''echo "  Custom height: OK"''
        else ''echo "  Custom height: FAILED"; exit 1''
      }
      ${
        if cfg.padding == 4
        then ''echo "  Custom padding: OK"''
        else ''echo "  Custom padding: FAILED"; exit 1''
      }
      ${
        if cfg.groupPadding == 12
        then ''echo "  Custom groupPadding: OK"''
        else ''echo "  Custom groupPadding: FAILED"; exit 1''
      }
      ${
        if !cfg.useAerospaceIntegration
        then ''echo "  Aerospace disabled: OK"''
        else ''echo "  Aerospace disabled: FAILED"; exit 1''
      }

      echo "All sketchybar options verified"
      touch $out
    '';

  # Test sketchybar theme integration from themes.nix
  sketchybarThemeTest = let
    themesModule = import ../modules/home-manager/themes.nix {
      inherit (pkgs) lib;
      inherit pkgs;
    };
    theme = themesModule._module.args.earthsong.sketchybarTheme;
  in
    pkgs.runCommand "test-sketchybar-theme"
    {}
    ''
      echo "=== Testing Sketchybar Theme Integration ==="

      # Verify theme structure has required top-level keys
      ${
        if theme ? colors
        then ''echo "  colors: present"''
        else ''echo "  colors: MISSING"; exit 1''
      }
      ${
        if theme ? font
        then ''echo "  font: present"''
        else ''echo "  font: MISSING"; exit 1''
      }

      # Verify color sub-attributes
      ${
        if theme.colors ? black
        then ''echo "  colors.black: present"''
        else ''echo "  colors.black: MISSING"; exit 1''
      }
      ${
        if theme.colors ? white
        then ''echo "  colors.white: present"''
        else ''echo "  colors.white: MISSING"; exit 1''
      }
      ${
        if theme.colors ? red
        then ''echo "  colors.red: present"''
        else ''echo "  colors.red: MISSING"; exit 1''
      }
      ${
        if theme.colors ? green
        then ''echo "  colors.green: present"''
        else ''echo "  colors.green: MISSING"; exit 1''
      }
      ${
        if theme.colors ? blue
        then ''echo "  colors.blue: present"''
        else ''echo "  colors.blue: MISSING"; exit 1''
      }
      ${
        if theme.colors ? yellow
        then ''echo "  colors.yellow: present"''
        else ''echo "  colors.yellow: MISSING"; exit 1''
      }
      ${
        if theme.colors ? orange
        then ''echo "  colors.orange: present"''
        else ''echo "  colors.orange: MISSING"; exit 1''
      }
      ${
        if theme.colors ? magenta
        then ''echo "  colors.magenta: present"''
        else ''echo "  colors.magenta: MISSING"; exit 1''
      }
      ${
        if theme.colors ? grey
        then ''echo "  colors.grey: present"''
        else ''echo "  colors.grey: MISSING"; exit 1''
      }
      ${
        if theme.colors ? bar
        then ''echo "  colors.bar: present"''
        else ''echo "  colors.bar: MISSING"; exit 1''
      }
      ${
        if theme.colors ? popup
        then ''echo "  colors.popup: present"''
        else ''echo "  colors.popup: MISSING"; exit 1''
      }
      ${
        if theme.colors ? bg1
        then ''echo "  colors.bg1: present"''
        else ''echo "  colors.bg1: MISSING"; exit 1''
      }
      ${
        if theme.colors ? bg2
        then ''echo "  colors.bg2: present"''
        else ''echo "  colors.bg2: MISSING"; exit 1''
      }
      ${
        if theme.colors.bar ? bg
        then ''echo "  colors.bar.bg: present"''
        else ''echo "  colors.bar.bg: MISSING"; exit 1''
      }
      ${
        if theme.colors.bar ? border
        then ''echo "  colors.bar.border: present"''
        else ''echo "  colors.bar.border: MISSING"; exit 1''
      }
      ${
        if theme.colors.popup ? bg
        then ''echo "  colors.popup.bg: present"''
        else ''echo "  colors.popup.bg: MISSING"; exit 1''
      }
      ${
        if theme.colors.popup ? border
        then ''echo "  colors.popup.border: present"''
        else ''echo "  colors.popup.border: MISSING"; exit 1''
      }

      # Verify font values
      ${
        if theme.font.text == "SF Pro"
        then ''echo "  font.text = SF Pro: OK"''
        else ''echo "  font.text: unexpected value"; exit 1''
      }
      ${
        if theme.font.numbers == "SF Mono"
        then ''echo "  font.numbers = SF Mono: OK"''
        else ''echo "  font.numbers: unexpected value"; exit 1''
      }

      # Verify color format (should be "#RRGGBB")
      ${
        if builtins.substring 0 1 theme.colors.black == "#"
        then ''echo "  Color format (#hex): OK"''
        else ''echo "  Color format: unexpected"; exit 1''
      }

      echo "All sketchybar theme tests passed"
      touch $out
    '';
}
