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

  # Test onepassword.nix config output for both platforms
  # Verifies that the module produces correct config for NixOS (isDarwin=false)
  # and Darwin (isDarwin=true) without importing options.nix (avoids readOnly isDarwin).
  onepasswordConfigOutputTest = let
    inherit (pkgs) lib;

    # Minimal option stubs shared by both evaluations
    commonStubModule = {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
      options.myConfig = {
        isDarwin = lib.mkOption {
          type = lib.types.bool;
          # No readOnly – tests override this
        };
        onepassword = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          enableGUI = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          enableSSHAgent = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          enableGitSigning = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          signingKey = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          enableSudo = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          tokenFile = lib.mkOption {
            type = lib.types.path;
            default = "/etc/opnix-token";
          };
          secrets = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
          };
        };
      };
      options.environment.systemPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
      };
    };

    # --- NixOS evaluation (isDarwin = false) ---
    nixosEval = lib.evalModules {
      modules = [
        commonStubModule
        {
          options.programs._1password = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            package = lib.mkOption {
              type = lib.types.package;
              default = pkgs._1password-cli;
            };
          };
        }
        ../modules/common/onepassword.nix
        {config._module.args = {inherit pkgs;};}
        {
          config.myConfig = {
            isDarwin = false;
            onepassword.enable = true;
          };
        }
      ];
    };
    nixosCfg = nixosEval.config;

    # --- Darwin evaluation (isDarwin = true) ---
    darwinEval = lib.evalModules {
      modules = [
        commonStubModule
        {
          # Darwin doesn't have programs._1password, so omit it
          options.programs = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
          };
        }
        ../modules/common/onepassword.nix
        {config._module.args = {inherit pkgs;};}
        {
          config.myConfig = {
            isDarwin = true;
            onepassword.enable = true;
          };
        }
      ];
    };
    darwinCfg = darwinEval.config;

    has1PasswordCli = builtins.any (p: (p.pname or "") == "_1password-cli" || (p.name or "") == pkgs._1password-cli.name) darwinCfg.environment.systemPackages;
  in
    pkgs.runCommand "test-onepassword-config-output"
    {}
    ''
      echo "=== Testing 1Password Config Output ==="

      # NixOS: programs._1password.enable should be true
      echo "  NixOS: programs._1password.enable = ${builtins.toJSON nixosCfg.programs._1password.enable}"
      ${
        if nixosCfg.programs._1password.enable
        then ''echo "  NixOS programs._1password.enable: OK"''
        else ''echo "  ERROR: NixOS programs._1password.enable should be true"; exit 1''
      }

      # NixOS: programs._1password.package should be set
      echo "  NixOS: programs._1password.package = ${nixosCfg.programs._1password.package.name}"
      ${
        if nixosCfg.programs._1password.package.name == pkgs._1password-cli.name
        then ''echo "  NixOS programs._1password.package: OK"''
        else ''echo "  ERROR: NixOS programs._1password.package mismatch"; exit 1''
      }

      # Darwin: environment.systemPackages should contain _1password-cli
      echo "  Darwin: environment.systemPackages count = ${toString (builtins.length darwinCfg.environment.systemPackages)}"
      ${
        if has1PasswordCli
        then ''echo "  Darwin environment.systemPackages contains _1password-cli: OK"''
        else ''echo "  ERROR: Darwin environment.systemPackages missing _1password-cli"; exit 1''
      }

      echo "All 1Password config output tests passed"
      touch $out
    '';

  # Test the hasOpnix conditional guard in onepassword.nix
  # Verifies that services.onepassword-secrets config is only produced
  # when the opnix option is available in options.services.
  onepasswordOpnixGuardTest = let
    inherit (pkgs) lib;

    # Shared option stubs
    commonStubModule = {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
      options.myConfig = {
        isDarwin = lib.mkOption {type = lib.types.bool;};
        onepassword = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          enableGUI = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          enableSSHAgent = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          enableGitSigning = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          signingKey = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          enableSudo = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          tokenFile = lib.mkOption {
            type = lib.types.path;
            default = "/etc/opnix-token";
          };
          secrets = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
          };
        };
      };
      options.environment.systemPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
      };
      # programs stub for Darwin path (no programs._1password)
      options.programs = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
    };

    # --- Evaluation WITHOUT opnix (no services.onepassword-secrets option) ---
    withoutOpnixEval = lib.evalModules {
      modules = [
        commonStubModule
        ../modules/common/onepassword.nix
        {config._module.args = {inherit pkgs;};}
        {
          config.myConfig = {
            isDarwin = true;
            onepassword = {
              enable = true;
              tokenFile = "/etc/opnix-token";
              secrets = {};
            };
          };
        }
      ];
    };
    withoutOpnixCfg = withoutOpnixEval.config;
    withoutHasOpnix = builtins.hasAttr "onepassword-secrets" (withoutOpnixCfg.services or {});

    # --- Evaluation WITH opnix (services.onepassword-secrets option available) ---
    withOpnixEval = lib.evalModules {
      modules = [
        commonStubModule
        {
          # Provide the opnix service option stub
          options.services.onepassword-secrets = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            tokenFile = lib.mkOption {
              type = lib.types.path;
              default = "/etc/opnix-token";
            };
            secrets = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = {};
            };
          };
        }
        ../modules/common/onepassword.nix
        {config._module.args = {inherit pkgs;};}
        {
          config.myConfig = {
            isDarwin = true;
            onepassword = {
              enable = true;
              tokenFile = "/etc/my-token";
              secrets = {
                testSecret = {
                  reference = "op://vault/item/field";
                };
              };
            };
          };
        }
      ];
    };
    withOpnixCfg = withOpnixEval.config;
  in
    pkgs.runCommand "test-onepassword-opnix-guard"
    {}
    ''
      echo "=== Testing 1Password Opnix Guard ==="

      # Without opnix: services should NOT have onepassword-secrets
      echo "  Without opnix module: services.onepassword-secrets present = ${builtins.toJSON withoutHasOpnix}"
      ${
        if !withoutHasOpnix
        then ''echo "  Without opnix: no onepassword-secrets config: OK"''
        else ''echo "  ERROR: onepassword-secrets should not be present without opnix module"; exit 1''
      }

      # With opnix: services.onepassword-secrets.enable should be true
      echo "  With opnix module: services.onepassword-secrets.enable = ${builtins.toJSON withOpnixCfg.services.onepassword-secrets.enable}"
      ${
        if withOpnixCfg.services.onepassword-secrets.enable
        then ''echo "  With opnix: services.onepassword-secrets.enable = true: OK"''
        else ''echo "  ERROR: services.onepassword-secrets.enable should be true"; exit 1''
      }

      # With opnix: tokenFile should be forwarded from myConfig
      echo "  With opnix module: services.onepassword-secrets.tokenFile = ${builtins.toJSON withOpnixCfg.services.onepassword-secrets.tokenFile}"
      ${
        if withOpnixCfg.services.onepassword-secrets.tokenFile == "/etc/my-token"
        then ''echo "  With opnix: tokenFile forwarded correctly: OK"''
        else ''echo "  ERROR: tokenFile not forwarded correctly"; exit 1''
      }

      # With opnix: secrets should be forwarded from myConfig
      echo "  With opnix module: secrets count = ${toString (builtins.length (builtins.attrNames withOpnixCfg.services.onepassword-secrets.secrets))}"
      ${
        if withOpnixCfg.services.onepassword-secrets.secrets ? testSecret
        then ''echo "  With opnix: secrets forwarded correctly: OK"''
        else ''echo "  ERROR: secrets not forwarded correctly"; exit 1''
      }

      echo "All 1Password opnix guard tests passed"
      touch $out
    '';
}
