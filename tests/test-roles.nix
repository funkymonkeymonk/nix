# Per-role evaluation and package inclusion tests
# Verifies each role evaluates cleanly and adds its expected packages
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  # withRoles: base + roles/default.nix + onepassword
  # (foundation always-on sets myConfig.onepassword.enable; opencode/claude/pi set
  #  myConfig.agent-skills.enable — both options now live in their owning modules)
  stubModules = stubs.withRoles;

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
                work.enable = true;
                entertainment.enable = true;
                agent-skills.enable = true;
                opencode.enable = true;
                claude.enable = true;
                pi.enable = true;
                assistant.enable = true;
                email-backup.enable = true;
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
    "work"
    "entertainment"
    "agent-skills"
    "opencode"
    "claude"
    "pi"
    "assistant"
    "email-backup"
  ];

  # Map of roles to their expected nix packages (name attr of the derivation)
  # Only includes packages added via environment.systemPackages (not homebrew)
  roleExpectedPackages = {
    developer = ["clang" "python3" "nodejs" "yarn" "k9s" "gh-dash" "yaks"];
    creative = ["ffmpeg" "imagemagick" "pandoc"];
    gaming = ["moonlight-qt"];
    desktop = []; # logseq removed due to electron-forge build hangs
    workstation = ["slack" "trippy" "unar"];
    # entertainment: NixOS packages (obs-studio, discord) are tested separately
    # in entertainmentNixosTest using linuxPkgs; they only appear on NixOS (isDarwin=false)
    opencode = ["opencode" "rtk"];
    claude = ["claude-code" "rtk"];
    pi = ["pi-coding-agent" "rtk"];
    assistant = ["himalaya" "gmailctl"];
    email-backup = ["isync" "notmuch" "restic"];
  };

  # Map of roles to cascade-enabled options
  roleCascades = {
    developer = {
      "zellij.enable" = true;
    };
    opencode = {"agent-skills.enable" = true;};
    claude = {"agent-skills.enable" = true;};
    pi = {
      "agent-skills.enable" = true;
      "pi.enable" = true;
      # Default local model served by the vllm-mlx registry via Bifrost.
      # Must match a model alias in myConfig.vllmMlx.models on hosts that
      # run the local stack (megamanx serves qwen3.8-27b).
      "pi.models.bifrost.modelId" = "qwen3.8-27b";
    };
    assistant = {"email-agent.enable" = true;};
    email-backup = {"email-backup.enable" = true;};
    foundation = {
      "onepassword.enable" = true;
      "syncthing.enable" = true;
    };
  };
  # Evaluate entertainment role in a NixOS-like context:
  # - Import only the modules needed (not via roles/default.nix, to avoid
  #   pulling in unrelated roles that would require broader stubs)
  # - Stub options.boot so isNixOS = builtins.hasAttr "boot" options is true
  entertainmentNixosEval =
    (lib.evalModules {
      modules =
        stubs.base
        ++ [
          # Stub options.boot so isNixOS = builtins.hasAttr "boot" options is true.
          # We import only entertainment.nix (not roles/default.nix) to avoid
          # pulling in unrelated roles that would require broader stubs.
          {
            options.boot = lib.mkOption {
              type = lib.types.anything;
              default = {};
            };
          }
          ../modules/roles/entertainment.nix
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
              roles.entertainment.enable = true;
            };
          }
        ];
    })
    .config;
  # Combined test: runs all role assertions in a single derivation
  # to reduce Nix per-derivation overhead during CI builds.
  allRoleTests = let
    evalTestScript = let
      evalChecks = lib.concatMapStringsSep "\n" (role: let
        evaluated = evalWithRole role;
        _forceEval = builtins.seq (builtins.toJSON evaluated.myConfig.roles) true;
      in
        if _forceEval
        then "echo \"  ${role}: evaluates OK\""
        else "echo \"  ${role}: FAILED\"; exit 1")
      allRoles;
    in ''
      echo "=== Testing Role Evaluation ==="
      ${evalChecks}
      echo "All roles evaluate successfully"
    '';

    compositionTestScript = let
      _forceEval = builtins.seq (builtins.toJSON evalAllRoles.myConfig.roles) true;
    in ''
      echo "=== Testing All Roles Composition ==="
      ${
        if _forceEval
        then ''
          echo "  All ${toString (builtins.length allRoles)} roles enabled simultaneously: OK"
          echo "  System packages count: ${toString (builtins.length evalAllRoles.environment.systemPackages)}"
          echo "  Enabled roles: ${builtins.concatStringsSep ", " evalAllRoles.myConfig.skills.enabledRoles}"
        ''
        else ''
          echo "  All roles composition: FAILED"
          exit 1
        ''
      }
      echo "All roles compose without conflicts"
    '';

    packageInclusionScript = let
      inclusionChecks =
        lib.concatMapStringsSep "\n" (
          role: let
            expectedPkgs = roleExpectedPackages.${role} or [];
            evaluated = evalWithRole role;
            actualPkgNames = map (p: p.name or (builtins.parseDrvName p.pname).name or "unknown") evaluated.environment.systemPackages;
          in
            if expectedPkgs == []
            then "echo \"  ${role}: no package requirements (homebrew-only or meta role)\""
            else
              lib.concatMapStringsSep "\n" (
                expectedPkg: let
                  found = builtins.any (actual: lib.hasInfix expectedPkg actual) actualPkgNames;
                in
                  if found
                  then "echo \"  ${role} -> ${expectedPkg}: found\""
                  else ''
                    echo "  ${role} -> ${expectedPkg}: NOT FOUND in [${builtins.concatStringsSep ", " actualPkgNames}]"
                    exit 1
                  ''
              )
              expectedPkgs
        )
        allRoles;
    in ''
      echo "=== Testing Role Package Inclusion ==="
      ${inclusionChecks}
      echo "All role packages are included correctly"
    '';

    cascadeScript = let
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
            then "echo \"  ${role} -> myConfig.${optPath} = ${builtins.toJSON expected}: OK\""
            else ''
              echo "  ${role} -> myConfig.${optPath}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}"
              exit 1
            ''
        ) (builtins.attrNames cascades))
      (builtins.attrNames roleCascades);
    in ''
      echo "=== Testing Role Cascade Activation ==="
      ${cascadeChecks}
      echo "All role cascades work correctly"
    '';

    deadDevOptionScript = let
      testEval = pkgs.lib.evalModules {
        modules =
          stubs.base
          ++ [
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
      developmentAttr = pkgs.lib.attrByPath ["development"] null testEval.config.myConfig;
      isDead = developmentAttr == null;
    in
      if isDead
      then ''
        echo "=== Testing myConfig.development removed ==="
        echo "  myConfig.development: absent (correctly removed)"
        echo "Dead development option successfully removed"
      ''
      else ''
        echo "=== Testing myConfig.development removed ==="
        echo "  myConfig.development: STILL PRESENT (should be removed)"
        echo "  Value: ${builtins.toJSON developmentAttr}"
        echo "FAIL: myConfig.development is dead code and must be removed"
        exit 1
      '';

    # Ollama service module and llm-host role were removed entirely — ollama
    # is no longer in use and the module couldn't be tested via nixosTest
    # anyway (Darwin-only, launchd/Homebrew, no systemd/nixpkgs dependency).
    deadOllamaLlmHostScript = let
      llmHostRoleAttr = pkgs.lib.attrByPath ["roles" "llm-host"] null evalAllRoles.myConfig;
      ollamaAttr = pkgs.lib.attrByPath ["ollama"] null evalAllRoles.myConfig;
      ollamaModuleFileRemoved = !(builtins.pathExists ../modules/services/ollama);
      llmHostRoleFileRemoved = !(builtins.pathExists ../modules/roles/llm-host.nix);
      allRemoved =
        llmHostRoleAttr
        == null
        && ollamaAttr == null
        && ollamaModuleFileRemoved
        && llmHostRoleFileRemoved;
    in
      if allRemoved
      then ''
        echo "=== Testing ollama/llm-host dead code removal ==="
        echo "  myConfig.roles.llm-host option: absent (correctly removed)"
        echo "  myConfig.ollama option: absent (correctly removed)"
        echo "  modules/services/ollama/: absent (correctly removed)"
        echo "  modules/roles/llm-host.nix: absent (correctly removed)"
        echo "Dead ollama/llm-host module successfully removed"
      ''
      else ''
        echo "=== Testing ollama/llm-host dead code removal ==="
        echo "  myConfig.roles.llm-host option present: ${builtins.toJSON (llmHostRoleAttr != null)}"
        echo "  myConfig.ollama option present: ${builtins.toJSON (ollamaAttr != null)}"
        echo "  modules/services/ollama/ present: ${builtins.toJSON (!ollamaModuleFileRemoved)}"
        echo "  modules/roles/llm-host.nix present: ${builtins.toJSON (!llmHostRoleFileRemoved)}"
        echo "FAIL: ollama/llm-host dead code must be fully removed"
        exit 1
      '';

    entertainmentNixosScript = let
      sysPkgNames = map (p: p.name or (builtins.parseDrvName (p.pname or "unknown")).name) entertainmentNixosEval.environment.systemPackages;
      obsFound = builtins.any (n: lib.hasInfix "obs-studio" n) sysPkgNames;
      discordFound = builtins.any (n: lib.hasInfix "discord" n) sysPkgNames;
    in ''
      echo "=== Testing Entertainment Role on NixOS ==="
      ${
        if obsFound
        then "echo \"  obs-studio in systemPackages: OK\""
        else ''
          echo "  obs-studio NOT found in systemPackages: [${builtins.concatStringsSep ", " sysPkgNames}]"
          exit 1
        ''
      }
      ${
        if discordFound
        then "echo \"  discord in systemPackages: OK\""
        else ''
          echo "  discord NOT found in systemPackages: [${builtins.concatStringsSep ", " sysPkgNames}]"
          exit 1
        ''
      }
      echo "All entertainment NixOS tests passed"
    '';
  in
    pkgs.runCommand "test-all-roles"
    {}
    ''
      ${evalTestScript}
      echo ""
      ${compositionTestScript}
      echo ""
      ${packageInclusionScript}
      echo ""
      ${cascadeScript}
      echo ""
      ${deadDevOptionScript}
      echo ""
      ${deadOllamaLlmHostScript}
      echo ""
      ${entertainmentNixosScript}
      echo ""
      echo "All role tests passed"
      touch $out
    '';
in {
  inherit allRoleTests;
  roleEvaluationTest = allRoleTests;
  allRolesCompositionTest = allRoleTests;
  rolePackageInclusionTest = allRoleTests;
  roleCascadeTest = allRoleTests;
  noDeadDevelopmentOptionTest = allRoleTests;
  noDeadOllamaLlmHostTest = allRoleTests;
  entertainmentNixosTest = allRoleTests;
}
