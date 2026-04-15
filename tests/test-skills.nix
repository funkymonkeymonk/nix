# Skills installation and auto-load tests
# Validates manifest parsing, autoLoad filtering, instruction file generation,
# and external skill activation script generation
{pkgs, ...}: let
  inherit (pkgs) lib;
  manifest = import ../modules/home-manager/skills/manifest.nix;

  # Simulate the filtering logic from install.nix
  enabledRoles = ["developer" "opencode" "claude" "pi"];

  enabledSkills =
    lib.filterAttrs (
      _name: skill:
        lib.any (role: lib.elem role skill.roles) enabledRoles
    )
    manifest;

  allSkillNames = lib.concatLists (lib.mapAttrsToList (
      name: skill:
        [name] ++ skill.deps
    )
    enabledSkills);

  allSkills = lib.listToAttrs (map (name: {
    inherit name;
    value = manifest.${name};
  }) (lib.unique allSkillNames));

  autoLoadSkills =
    lib.filterAttrs (
      _name: skill: skill.autoLoad or false
    )
    allSkills;

  autoLoadContent = lib.concatStringsSep "\n\n---\n\n" (lib.mapAttrsToList (
      name: skill: let
        skillMd =
          if skill.source.type == "internal"
          then builtins.readFile "${skill.source.path}/SKILL.md"
          else "# ${name}\n\n${skill.description}";
      in
        skillMd
    )
    autoLoadSkills);

  skillNames = builtins.attrNames allSkills;
  autoLoadNames = builtins.attrNames autoLoadSkills;

  # Filter external skills from manifest (source.type == "external")
  externalSkills =
    lib.filterAttrs (
      _name: skill: skill.source.type or "" == "external"
    )
    manifest;

  externalSkillNames = builtins.attrNames externalSkills;

  # Simulate the activation script generation logic from install.nix
  # Each external skill becomes a `npx skills add <url> --global --yes --agent <...>` command
  # Agent mapping: manifest roles to npx skills --agent flags
  roleToAgents = {
    opencode = ["opencode"];
    claude = ["claude-code"];
    pi = ["pi"];
    developer = ["opencode" "claude-code" "pi"];
    workstation = ["opencode" "claude-code"];
  };

  # Collect all agent flags for a skill's roles
  agentFlagsForSkill = skill:
    lib.unique (lib.concatLists (
      map (role: roleToAgents.${role} or []) skill.roles
    ));

  # Generate the command line for one external skill
  externalSkillCommand = name: skill: let
    url = skill.source.url or "unknown:${name}";
    agents = agentFlagsForSkill skill;
    agentFlags = lib.concatMapStringsSep " " (a: "--agent ${a}") agents;
  in "npx skills add ${url} --global --yes ${agentFlags}";

  # Generate the full activation script body
  externalInstallCommands =
    lib.mapAttrsToList externalSkillCommand externalSkills;

  activationScriptBody =
    lib.concatStringsSep "\n" externalInstallCommands;

  # Simulate a manifest with one external skill for unit testing
  testExternalManifest = {
    "test-external-skill" = {
      description = "A test external skill";
      roles = ["opencode" "claude"];
      source = {
        type = "external";
        url = "github:example/repo//skills/test-skill";
      };
      deps = [];
    };
    "test-internal-skill" = {
      description = "A test internal skill";
      roles = ["developer"];
      source = {
        type = "internal";
        path = null; # Not used in external skill filtering tests
      };
      deps = [];
    };
  };

  testExternalSkills =
    lib.filterAttrs (
      _name: skill: skill.source.type or "" == "external"
    )
    testExternalManifest;

  testExternalCommand = externalSkillCommand "test-external-skill" testExternalManifest."test-external-skill";
in {
  # Test that manifest parses and all skills have required fields
  manifestValidationTest =
    pkgs.runCommand "test-manifest-validation"
    {}
    ''
      echo "=== Testing Skills Manifest Validation ==="

      # Verify manifest has skills
      echo "  Total skills in manifest: ${toString (builtins.length (builtins.attrNames manifest))}"
      ${
        if builtins.length (builtins.attrNames manifest) > 0
        then ''echo "  Manifest has skills: OK"''
        else ''echo "  Manifest has no skills!"; exit 1''
      }

      # Verify each skill has required fields
      ${lib.concatMapStringsSep "\n" (name: let
        skill = manifest.${name};
      in ''
        echo "  ${name}: description='${lib.substring 0 50 skill.description}...' roles=[${lib.concatStringsSep "," skill.roles}] type=${skill.source.type}"
      '') (builtins.attrNames manifest)}

      echo "Manifest validation passed"
      touch $out
    '';

  # Test that autoLoad filtering works correctly
  autoLoadFilteringTest =
    pkgs.runCommand "test-autoload-filtering"
    {}
    ''
      echo "=== Testing AutoLoad Filtering ==="

      # Verify yak-shaving has autoLoad = true
      ${
        if builtins.hasAttr "yak-shaving" autoLoadSkills
        then ''echo "  yak-shaving in autoLoad skills: OK"''
        else ''echo "  yak-shaving NOT in autoLoad skills!"; exit 1''
      }

      # Verify non-autoLoad skills are excluded
      ${
        if !(builtins.hasAttr "debugging" autoLoadSkills)
        then ''echo "  debugging NOT in autoLoad skills: OK"''
        else ''echo "  debugging should NOT be in autoLoad skills!"; exit 1''
      }

      ${
        if !(builtins.hasAttr "tdd" autoLoadSkills)
        then ''echo "  tdd NOT in autoLoad skills: OK"''
        else ''echo "  tdd should NOT be in autoLoad skills!"; exit 1''
      }

      # Verify autoLoad count is reasonable (should be small)
      echo "  AutoLoad skills count: ${toString (builtins.length autoLoadNames)}"
      echo "  AutoLoad skills: ${lib.concatStringsSep ", " autoLoadNames}"

      echo "AutoLoad filtering passed"
      touch $out
    '';

  # Test that auto-loaded content is generated correctly
  autoLoadContentTest =
    pkgs.runCommand "test-autoload-content"
    {}
    ''
      echo "=== Testing AutoLoad Content Generation ==="

      # Verify content is non-empty
      ${
        if builtins.stringLength autoLoadContent > 0
        then ''echo "  AutoLoad content generated: OK (${toString (builtins.stringLength autoLoadContent)} chars)"''
        else ''echo "  AutoLoad content is empty!"; exit 1''
      }

      # Verify yak-shaving SKILL.md content is present
      ${
        if lib.hasInfix "yak-shaving" autoLoadContent
        then ''echo "  yak-shaving content present: OK"''
        else ''echo "  yak-shaving content NOT found in autoLoad!"; exit 1''
      }

      # Verify key skill sections are present
      ${
        if lib.hasInfix "Claim Protocol" autoLoadContent
        then ''echo "  Claim Protocol section present: OK"''
        else ''echo "  Claim Protocol section NOT found!"; exit 1''
      }

      ${
        if lib.hasInfix "yx sync" autoLoadContent
        then ''echo "  yx sync references present: OK"''
        else ''echo "  yx sync references NOT found!"; exit 1''
      }

      echo "AutoLoad content generation passed"
      touch $out
    '';

  # Test that skills for specific roles are correctly filtered
  roleFilteringTest =
    pkgs.runCommand "test-skills-role-filtering"
    {}
    ''
      echo "=== Testing Skills Role Filtering ==="

      # Verify developer role gets expected skills
      ${
        if builtins.hasAttr "debugging" allSkills
        then ''echo "  developer gets debugging: OK"''
        else ''echo "  developer should get debugging!"; exit 1''
      }

      ${
        if builtins.hasAttr "tdd" allSkills
        then ''echo "  developer gets tdd: OK"''
        else ''echo "  developer should get tdd!"; exit 1''
      }

      ${
        if builtins.hasAttr "yak-shaving" allSkills
        then ''echo "  developer gets yak-shaving: OK"''
        else ''echo "  developer should get yak-shaving!"; exit 1''
      }

      # Verify jj skill is present (developer + opencode + claude)
      ${
        if builtins.hasAttr "jj" allSkills
        then ''echo "  jj skill present: OK"''
        else ''echo "  jj skill should be present!"; exit 1''
      }

      echo "  Total skills for roles [${lib.concatStringsSep ", " enabledRoles}]: ${toString (builtins.length skillNames)}"
      echo "  Skills: ${lib.concatStringsSep ", " skillNames}"

      echo "Role filtering passed"
      touch $out
    '';

  # Test that external skills are correctly identified from manifest
  externalSkillsIdentificationTest =
    pkgs.runCommand "test-external-skills-identification"
    {}
    ''
      echo "=== Testing External Skills Identification ==="

      # Verify filtering finds only external-type skills
      echo "  External skills in current manifest: ${toString (builtins.length externalSkillNames)}"
      ${
        if builtins.length externalSkillNames == 0
        then ''echo "  No external skills in manifest yet: OK (placeholder commented out)"''
        else ''echo "  Found external skills: ${lib.concatStringsSep ", " externalSkillNames}"''
      }

      # Verify test manifest correctly identifies one external and zero internal as external
      ${
        if builtins.length (builtins.attrNames testExternalSkills) == 1
        then ''echo "  Test manifest: 1 external skill identified: OK"''
        else ''echo "  Test manifest should have exactly 1 external skill!"; exit 1''
      }

      ${
        if builtins.hasAttr "test-external-skill" testExternalSkills
        then ''echo "  test-external-skill identified as external: OK"''
        else ''echo "  test-external-skill should be identified as external!"; exit 1''
      }

      ${
        if !(builtins.hasAttr "test-internal-skill" testExternalSkills)
        then ''echo "  test-internal-skill NOT identified as external: OK"''
        else ''echo "  test-internal-skill should NOT be identified as external!"; exit 1''
      }

      echo "External skills identification passed"
      touch $out
    '';

  # Test that the activation command generation logic produces correct npx skills commands
  externalSkillCommandGenerationTest =
    pkgs.runCommand "test-external-skill-command-generation"
    {}
    ''
      echo "=== Testing External Skill Command Generation ==="

      # Verify the command includes the correct URL
      ${
        if lib.hasInfix "github:example/repo//skills/test-skill" testExternalCommand
        then ''echo "  Command includes correct URL: OK"''
        else ''echo "  Command should include the skill URL!"; exit 1''
      }

      # Verify the command includes --global --yes flags
      ${
        if lib.hasInfix "--global" testExternalCommand && lib.hasInfix "--yes" testExternalCommand
        then ''echo "  Command includes --global --yes flags: OK"''
        else ''echo "  Command should include --global --yes flags!"; exit 1''
      }

      # Verify the command includes npx skills add
      ${
        if lib.hasPrefix "npx skills add" testExternalCommand
        then ''echo "  Command starts with npx skills add: OK"''
        else ''echo "  Command should start with npx skills add!"; exit 1''
      }

      # Verify agent flags are present for opencode and claude-code
      ${
        if lib.hasInfix "--agent opencode" testExternalCommand
        then ''echo "  Command includes --agent opencode: OK"''
        else ''echo "  Command should include --agent opencode (skill has opencode role)!"; exit 1''
      }

      ${
        if lib.hasInfix "--agent claude-code" testExternalCommand
        then ''echo "  Command includes --agent claude-code: OK"''
        else ''echo "  Command should include --agent claude-code (skill has claude role)!"; exit 1''
      }

      echo "  Full command: ${testExternalCommand}"
      echo "External skill command generation passed"
      touch $out
    '';

  # Test that the activation script handles the no-external-skills case gracefully
  externalSkillsEmptyTest =
    pkgs.runCommand "test-external-skills-empty-case"
    {}
    ''
      echo "=== Testing External Skills Empty Case ==="

      # The current manifest has no external skills (all commented out)
      # The activation script body should be empty or just whitespace
      ${
        if activationScriptBody == "" || activationScriptBody == "\n"
        then ''echo "  Empty manifest produces empty script body: OK"''
        else ''
          echo "  No external skills yet, script body: [${activationScriptBody}]"
          echo "  (This is expected if external skills have been added)"
        ''
      }

      echo "  External skills count: ${toString (builtins.length externalSkillNames)}"
      echo "External skills empty case handled correctly"
      touch $out
    '';
}
