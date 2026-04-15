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
    desktop = ["logseq" "super-productivity"];
    workstation = ["slack" "trippy" "unar"];
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
      "development.enable" = true;
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
}
