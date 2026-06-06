# Per-role evaluation and package inclusion tests
# Verifies each role evaluates cleanly and adds its expected packages
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Shared stub modules needed by evalModules to provide options
  # that role modules may reference (environment, programs, homebrew, etc.)
  stubModules = [
    ../modules/common/options.nix
    ../modules/roles/default.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
      options.environment = {
        systemPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
        };
        variables = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
        sessionVariables = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
        shellAliases = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
        etc = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
        };
      };
      options.programs = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      options.homebrew = lib.mkOption {
        type = lib.types.anything;
        default = {};
      };
      # Note: We intentionally do NOT stub NixOS-specific options (boot, networking,
      # systemd, services). This means on Darwin, microvm-host evaluates as a no-op
      # since isNixOS = builtins.hasAttr "boot" options => false.
      # On NixOS (CI), these options exist natively.
      # Stub for microvm.vms (referenced by microvm-host role, guarded by isNixOS)
      options.microvm = lib.mkOption {
        type = lib.types.anything;
        default = {};
      };
      config.microvm.vms = {};
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  # Evaluate llm-host role with default sharedModels
  llmHostDefaultEval =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
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
              roles.llm-host.enable = true;
            };
          }
        ];
    })
    .config;

  # Evaluate llm-host role with custom sharedModels
  llmHostCustomEval =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
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
              roles.llm-host.enable = true;
              sharedModels = ["llama3.2" "mistral:7b"];
            };
          }
        ];
    })
    .config;

  # Helper: evaluate modules with a specific role enabled
  evalWithRole = roleName:
    (lib.evalModules {
      modules =
        stubModules
        ++ [
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
              roles.${roleName}.enable = true;
            };
          }
        ];
    })
    .config;

  # Helper: evaluate with ALL roles enabled
  evalAllRoles =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
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
              roles = {
                foundation.enable = true;
                developer.enable = true;
                creative.enable = true;
                gaming.enable = true;
                desktop.enable = true;
                workstation.enable = true;
                entertainment.enable = true;
                agent-skills.enable = true;
                opencode.enable = true;
                claude.enable = true;
                pi.enable = true;
                llm-host.enable = true;
                assistant.enable = true;
                email-backup.enable = true;
                microvm-host.enable = true;
              };
            };
          }
        ];
    })
    .config;

  # All role names for iteration
  allRoles = [
    "foundation"
    "developer"
    "creative"
    "gaming"
    "desktop"
    "workstation"
    "entertainment"
    "agent-skills"
    "opencode"
    "claude"
    "pi"
    "llm-host"
    "assistant"
    "email-backup"
    "microvm-host"
  ];

  # Map of roles to their expected nix packages (name attr of the derivation)
  # Only includes packages added via environment.systemPackages (not homebrew)
  roleExpectedPackages = {
    developer = ["clang" "python3" "nodejs" "yarn" "k9s" "gh-dash" "yaks"];
    creative = ["ffmpeg" "imagemagick" "pandoc"];
    gaming = ["moonlight-qt"];
    desktop = ["logseq"];
    workstation = ["slack" "trippy" "unar"];
    # entertainment: NixOS packages (obs-studio, discord) are tested separately
    # in entertainmentNixosTest using linuxPkgs; they only appear on NixOS (isDarwin=false)
    opencode = ["opencode" "rtk"];
    claude = ["claude-code" "rtk"];
    pi = ["pi-coding-agent" "rtk"];
    llm-host = ["ollama"];
    assistant = ["himalaya" "gmailctl"];
    email-backup = ["isync" "notmuch" "restic"];
    # microvm-host packages are NixOS-only (guarded by isNixOS check).
    # On Darwin, the role is a no-op and adds no packages.
  };

  # Map of roles to cascade-enabled options
  roleCascades = {
    developer = {
      "fjj.enable" = true;
      "zellij.enable" = true;
    };
    opencode = {"agent-skills.enable" = true;};
    claude = {"agent-skills.enable" = true;};
    pi = {
      "agent-skills.enable" = true;
      "pi.enable" = true;
    };
    llm-host = {"ollama.enable" = true;};
    assistant = {"email-agent.enable" = true;};
    email-backup = {"email-backup.enable" = true;};
    foundation = {
      "onepassword.enable" = true;
      "syncthing.enable" = true;
    };
  };
  # Evaluate entertainment role in a NixOS-like context:
  # - Import only the modules needed (not via roles/default.nix to avoid
  #   microvm-host which would require networking.* stubs)
  # - Stub options.boot so isNixOS = builtins.hasAttr "boot" options is true
  entertainmentNixosEval =
    (lib.evalModules {
      modules = [
        ../modules/common/options.nix
        ../modules/roles/entertainment.nix
        {
          options.nixpkgs.hostPlatform = lib.mkOption {
            type = lib.types.anything;
            default = {inherit (pkgs.stdenv.hostPlatform) system;};
          };
          options.environment = {
            systemPackages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [];
            };
          };
          options.programs = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
          };
          options.homebrew = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
          # Stub options.boot so isNixOS = builtins.hasAttr "boot" options is true.
          # Safe here because we do NOT import microvm-host (which needs networking.*).
          options.boot = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
          options.microvm = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
          config.microvm.vms = {};
        }
        {
          config._module.args = {inherit pkgs;};
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
            roles.entertainment.enable = true;
          };
        }
      ];
    })
    .config;
in {
  # Test that each role evaluates without errors
  roleEvaluationTest =
    pkgs.runCommand "test-role-evaluation"
    {}
    ''
      echo "=== Testing Role Evaluation ==="

      ${lib.concatMapStringsSep "\n" (role: let
          # Force evaluation by accessing the config
          evaluated = evalWithRole role;
          _forceEval = builtins.seq (builtins.toJSON evaluated.myConfig.roles) true;
        in ''
          ${
            if _forceEval
            then ''echo "  ${role}: evaluates OK"''
            else ''echo "  ${role}: FAILED"; exit 1''
          }
        '')
        allRoles}

      echo "All roles evaluate successfully"
      touch $out
    '';

  # Test that enabling all roles simultaneously doesn't conflict
  allRolesCompositionTest =
    pkgs.runCommand "test-all-roles-composition"
    {}
    ''
      echo "=== Testing All Roles Composition ==="

      # Force evaluation of the combined config
      ${let
        _forceEval = builtins.seq (builtins.toJSON evalAllRoles.myConfig.roles) true;
      in
        if _forceEval
        then ''
          echo "  All 12 roles enabled simultaneously: OK"
          echo "  System packages count: ${toString (builtins.length evalAllRoles.environment.systemPackages)}"
          echo "  Enabled roles: ${builtins.concatStringsSep ", " evalAllRoles.myConfig.skills.enabledRoles}"
        ''
        else ''
          echo "  All roles composition: FAILED"
          exit 1
        ''}

      echo "All roles compose without conflicts"
      touch $out
    '';

  # Test that each role adds its expected packages
  rolePackageInclusionTest = let
    # Build verification commands for each role that has expected packages
    verificationCommands =
      lib.concatMapStringsSep "\n" (
        role: let
          expectedPkgs = roleExpectedPackages.${role} or [];
          evaluated = evalWithRole role;
          actualPkgNames = map (p: p.name or (builtins.parseDrvName p.pname).name or "unknown") evaluated.environment.systemPackages;
        in
          if expectedPkgs == []
          then ''echo "  ${role}: no package requirements (homebrew-only or meta role)"''
          else
            lib.concatMapStringsSep "\n" (
              expectedPkg: let
                found = builtins.any (actual:
                  lib.hasInfix expectedPkg actual)
                actualPkgNames;
              in
                if found
                then ''echo "  ${role} -> ${expectedPkg}: found"''
                else ''
                  echo "  ${role} -> ${expectedPkg}: NOT FOUND in [${builtins.concatStringsSep ", " actualPkgNames}]"
                  exit 1
                ''
            )
            expectedPkgs
      )
      allRoles;
  in
    pkgs.runCommand "test-role-package-inclusion"
    {}
    ''
      echo "=== Testing Role Package Inclusion ==="

      ${verificationCommands}

      echo "All role packages are included correctly"
      touch $out
    '';

  # Test that role cascades work correctly
  roleCascadeTest = let
    cascadeChecks = lib.concatMapStringsSep "\n" (role: let
      cascades = roleCascades.${role} or {};
    in
      lib.concatMapStringsSep "\n" (
        optPath: let
          expected = cascades.${optPath};
          evaluated = evalWithRole role;
          actual = lib.attrByPath (lib.splitString "." optPath) null evaluated.myConfig;
        in
          if actual == expected
          then ''echo "  ${role} -> myConfig.${optPath} = ${builtins.toJSON expected}: OK"''
          else ''
            echo "  ${role} -> myConfig.${optPath}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}"
            exit 1
          ''
      ) (builtins.attrNames cascades))
    (builtins.attrNames roleCascades);
  in
    pkgs.runCommand "test-role-cascades"
    {}
    ''
      echo "=== Testing Role Cascade Activation ==="

      ${cascadeChecks}

      echo "All role cascades work correctly"
      touch $out
    '';

  # Test that dead myConfig.development option has been removed from options.nix.
  # This option was declared and set (by developer role) but never consumed by any module.
  # The actual developer role check uses config.myConfig.roles.developer.enable.
  noDeadDevelopmentOptionTest = let
    testEval = pkgs.lib.evalModules {
      modules = [
        ../modules/common/options.nix
        {
          options.nixpkgs.hostPlatform = pkgs.lib.mkOption {
            type = pkgs.lib.types.anything;
            default = {inherit (pkgs.stdenv.hostPlatform) system;};
          };
        }
        {config._module.args = {inherit pkgs;};}
        {
          config.myConfig.users = [
            {
              name = "testuser";
              email = "test@example.com";
              fullName = "Test User";
              isAdmin = true;
              sshIncludes = [];
            }
          ];
        }
      ];
    };
    # If myConfig.development was removed, attrByPath returns the sentinel null.
    developmentAttr = pkgs.lib.attrByPath ["development"] null testEval.config.myConfig;
    isDead = developmentAttr == null;
  in
    pkgs.runCommand "test-no-dead-development-option"
    {}
    (
      if isDead
      then ''
        echo "=== Testing myConfig.development removed ==="
        echo "  myConfig.development: absent (correctly removed)"
        echo "Dead development option successfully removed"
        touch $out
      ''
      else ''
        echo "=== Testing myConfig.development removed ==="
        echo "  myConfig.development: STILL PRESENT (should be removed)"
        echo "  Value: ${builtins.toJSON developmentAttr}"
        echo "FAIL: myConfig.development is dead code and must be removed"
        exit 1
      ''
    );

  # Test that llm-host role wires myConfig.sharedModels into ollama.models
  llmHostSharedModelsTest = let
    defaultModels = llmHostDefaultEval.myConfig.sharedModels;
    defaultOllamaModels = llmHostDefaultEval.myConfig.ollama.models;
    customOllamaModels = llmHostCustomEval.myConfig.ollama.models;
  in
    pkgs.runCommand "test-llm-host-shared-models"
    {}
    ''
      echo "=== Testing llm-host sharedModels wiring ==="

      ${
        if defaultModels == defaultOllamaModels
        then ''echo "  default sharedModels propagated to ollama.models: OK"''
        else ''
          echo "  sharedModels default should propagate to ollama.models!"
          echo "  sharedModels = ${builtins.toJSON defaultModels}"
          echo "  ollama.models = ${builtins.toJSON defaultOllamaModels}"
          exit 1
        ''
      }

      ${
        if customOllamaModels == ["llama3.2" "mistral:7b"]
        then ''echo "  custom sharedModels reflected in ollama.models: OK"''
        else ''
          echo "  custom sharedModels should be reflected in ollama.models!"
          echo "  expected = [\"llama3.2\" \"mistral:7b\"]"
          echo "  got = ${builtins.toJSON customOllamaModels}"
          exit 1
        ''
      }

      echo "All llm-host sharedModels tests passed"
      touch $out
    '';

  # Test entertainment role on NixOS: obs-studio and discord in systemPackages.
  # entertainmentNixosEval has options.boot stubbed so isNixOS=true in the module,
  # meaning packages are always added regardless of host platform.
  entertainmentNixosTest = let
    sysPkgNames = map (p: p.name or (builtins.parseDrvName (p.pname or "unknown")).name) entertainmentNixosEval.environment.systemPackages;
    obsFound = builtins.any (n: lib.hasInfix "obs-studio" n) sysPkgNames;
    discordFound = builtins.any (n: lib.hasInfix "discord" n) sysPkgNames;
  in
    pkgs.runCommand "test-entertainment-nixos"
    {}
    ''
      echo "=== Testing Entertainment Role on NixOS ==="

      ${
        if obsFound
        then ''echo "  obs-studio in systemPackages: OK"''
        else ''
          echo "  obs-studio NOT found in systemPackages: [${builtins.concatStringsSep ", " sysPkgNames}]"
          exit 1
        ''
      }

      ${
        if discordFound
        then ''echo "  discord in systemPackages: OK"''
        else ''
          echo "  discord NOT found in systemPackages: [${builtins.concatStringsSep ", " sysPkgNames}]"
          exit 1
        ''
      }

      echo "All entertainment NixOS tests passed"
      touch $out
    '';
}
