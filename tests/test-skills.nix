# Tests for repository-backed skills and their optional Nix metadata.
{
  pkgs,
  skillsRepo,
  ...
}: let
  inherit (pkgs) lib;
  hmLib = import ../modules/home-manager/lib.nix {inherit lib;};
  manifest = import ../modules/home-manager/skills/manifest.nix;
  sourceSkillDirs = hmLib.mkRepoSkillDirs {inherit skillsRepo;};
  sourceSkillNames = builtins.sort builtins.lessThan (builtins.attrNames sourceSkillDirs);
  metadataSkillNames = builtins.sort builtins.lessThan (builtins.attrNames manifest);
  allSkillsWithoutRoles =
    (hmLib.mkFullSkillDirs {
      enabledRoles = [];
      inherit skillsRepo;
    }).skillDirs;
  metadataIsValid =
    lib.all (
      name:
        builtins.hasAttr name sourceSkillDirs
        && builtins.hasAttr "description" manifest.${name}
        && builtins.hasAttr "roles" manifest.${name}
    )
    metadataSkillNames;
  sourceHasRequiredSkillFiles =
    lib.all (
      name: builtins.pathExists (sourceSkillDirs.${name} + "/SKILL.md")
    )
    sourceSkillNames;
in {
  manifestValidationTest = pkgs.runCommand "test-skills-metadata" {} ''
    echo "=== Testing optional skill metadata references repository skills ==="
    ${
      if metadataIsValid
      then ''echo "  All metadata names resolve to repository skills and have descriptions and roles: OK"''
      else ''echo "  Metadata contains an unknown skill or an incomplete entry"; exit 1''
    }
    ${
      if builtins.length metadataSkillNames > 0
      then ''echo "  Metadata entries: ${lib.concatStringsSep ", " metadataSkillNames}"''
      else ''echo "  Expected optional metadata entries"; exit 1''
    }
    touch $out
  '';

  repositoryInstallationTest = pkgs.runCommand "test-all-repository-skills" {} ''
    echo "=== Testing all repository skills are available regardless of roles ==="
    expected='${lib.concatStringsSep " " sourceSkillNames}'
    actual='${lib.concatStringsSep " " (builtins.sort builtins.lessThan (builtins.attrNames allSkillsWithoutRoles))}'
    if [[ "$actual" != "$expected" ]]; then
      echo "Expected repository skills: $expected"
      echo "Resolved skills:           $actual"
      exit 1
    fi
    ${
      if sourceHasRequiredSkillFiles
      then ''echo "  Every installed directory contains SKILL.md: OK"''
      else ''echo "  A repository skill directory has no SKILL.md"; exit 1''
    }
    echo "All pinned repository skills are available"
    touch $out
  '';
}
