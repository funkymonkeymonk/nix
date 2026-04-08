# Skills installation and auto-load tests
# Validates manifest parsing, autoLoad filtering, and instruction file generation
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
}
