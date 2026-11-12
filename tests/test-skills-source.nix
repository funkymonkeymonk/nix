# Tests for installing skill directories from a repository source.
{pkgs, ...}: let
  inherit (pkgs) lib;
  skillsRepo = ./fixtures/personal-skills;
  sourceRoot = skillsRepo + "/skills";
  sourceEntries = builtins.readDir sourceRoot;
  sourceSkillNames = builtins.sort builtins.lessThan (
    lib.filter (
      name:
        sourceEntries.${name}
        == "directory"
        && builtins.pathExists (sourceRoot + "/${name}/SKILL.md")
    )
    (builtins.attrNames sourceEntries)
  );
  homeFileOptions = {
    options.home.file = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
  };
  osConfig = {
    myConfig.skills = {
      enabledRoles = ["developer"];
      repository = skillsRepo;
    };
  };
  evaluated = lib.evalModules {
    modules = [
      homeFileOptions
      {
        config._module.args = {inherit osConfig pkgs;};
      }
      ../modules/home-manager/skills/canonical-install.nix
    ];
  };
  installed = evaluated.config.home.file;
  installedNames = builtins.sort builtins.lessThan (
    map (path: lib.removePrefix ".agents/skills/" path) (
      builtins.filter (lib.hasPrefix ".agents/skills/") (builtins.attrNames installed)
    )
  );
  expectedSource = name: toString (sourceRoot + "/${name}");
  hasExpectedSource = name:
    toString (installed.".agents/skills/${name}".source or "") == expectedSource name;
  rootFlakeText = builtins.readFile ../flake.nix;
  usersModuleText = builtins.readFile ../modules/common/users.nix;
in {
  publicRepositoryInputIsDeclared = pkgs.runCommand "test-public-personal-skills-input" {} ''
    echo "=== Testing the public skills repository is a raw flake input ==="
    ${
      if
        lib.hasInfix ''personal-skills.url = "github:funkymonkeymonk/skills";'' rootFlakeText
        && lib.hasInfix "personal-skills.flake = false;" rootFlakeText
      then ''echo "  Public personal-skills input is declared with flake = false: OK"''
      else ''echo "  Public personal-skills raw flake input is not declared"; exit 1''
    }
    touch $out
  '';

  activationInstallerIsRemoved = pkgs.runCommand "test-no-runtime-skills-installer" {} ''
    echo "=== Testing skill deployment does not fetch at activation ==="
    ${
      if
        !(builtins.pathExists ../modules/home-manager/skills/install.nix)
        && !(lib.hasInfix "skills/install.nix" usersModuleText)
      then ''echo "  Runtime installer file and import are absent: OK"''
      else ''echo "  Runtime npx installer is still wired into Home Manager"; exit 1''
    }
    touch $out
  '';

  sourceSkillsReplaceManifestSkills = pkgs.runCommand "test-personal-skills-source-install" {} ''
    echo "=== Testing repository skills are installed from their source tree ==="
    expected='${lib.concatStringsSep " " sourceSkillNames}'
    actual='${lib.concatStringsSep " " installedNames}'
    if [[ "$actual" != "$expected" ]]; then
      echo "Expected source skills: $expected"
      echo "Installed skills:       $actual"
      exit 1
    fi
    ${lib.concatMapStringsSep "\n" (
        name:
          if hasExpectedSource name
          then ''echo "  ${name} comes from the repository input: OK"''
          else ''echo "  ${name} does not use its repository source path"; exit 1''
      )
      sourceSkillNames}
    echo "Repository skill directories are installed from the source tree"
    touch $out
  '';
}
