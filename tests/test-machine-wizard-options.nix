# Invariants for the interactive machine wizard's platform-specific choices.
{pkgs, ...}: let
  inherit (pkgs) lib;

  options = import ../library/machines/wizard-options.nix;
  expectedPlatforms = ["aarch64-darwin" "aarch64-linux" "x86_64-linux"];
  optionDefinitions = modulePath: let
    module = import modulePath;
    evaluatedModule = module {
      inherit (pkgs) lib;
      inherit pkgs;
      config = {};
      options = {};
      inputs = {};
    };
  in
    evaluatedModule.options or {};
  expectedArchetypeModules = {
    aarch64-darwin = [
      "library/archetypes/workstation-darwin.nix"
      "library/archetypes/vm-management-darwin.nix"
      "library/archetypes/headless-inference-darwin.nix"
    ];
    aarch64-linux = [
      "library/archetypes/headless-server-nixos.nix"
      "library/archetypes/type-server.nix"
    ];
    x86_64-linux = [
      "library/archetypes/desktop-nixos.nix"
      "library/archetypes/headless-server-nixos.nix"
      "library/archetypes/type-server.nix"
    ];
  };
  commonModuleText = builtins.readFile ../modules/default.nix;
  roleStackText = builtins.readFile ../modules/roles/default.nix;
  listedRoles = lib.unique (lib.concatMap (platform: options.${platform}.roles) expectedPlatforms);
  listedRoleModulePath = role: ../modules/roles/${role}.nix;
  existingListedRoles = builtins.filter (role: builtins.pathExists (listedRoleModulePath role)) listedRoles;
  roleOptions =
    (lib.evalModules {
      modules =
        [{options = optionDefinitions ../modules/common/options.nix;}]
        ++ map (role: {options = optionDefinitions (listedRoleModulePath role);}) existingListedRoles;
    }).options.myConfig.roles;
  allListedRoleModulesExist = builtins.all (role: builtins.pathExists (listedRoleModulePath role)) listedRoles;
  allListedRoleModulesAreImported = builtins.all (role:
    lib.hasInfix "./${role}.nix" roleStackText)
  listedRoles;

  fail = message: throw "machine-wizard-options: ${message}";
  assertThat = condition: message:
    if condition
    then true
    else fail message;
  hasUnique = values: builtins.length values == builtins.length (lib.unique values);

  checkPlatform = platform: entry: let
    isDarwin = platform == "aarch64-darwin";
    expectedKind =
      if isDarwin
      then "darwin"
      else "nixos";
    archetypeModules = map (choice: choice.module) entry.archetypes;
    allRolesDefined = builtins.all (role: builtins.hasAttr role roleOptions) entry.roles;
    correctlyScopedArchetypes = builtins.all (choice: choice.kind == expectedKind) entry.archetypes;
    matchesReviewedArchetypeMatrix = archetypeModules == expectedArchetypeModules.${platform};
    existingArchetypes = builtins.all (module: builtins.pathExists (../. + "/${module}")) archetypeModules;
    importableArchetypes = builtins.all (module:
      builtins.isFunction (import (../. + "/${module}")))
    archetypeModules;
    validArchetypeLabels = builtins.all (choice:
      choice.label != "" && choice.module != "")
    entry.archetypes;
  in
    assertThat (builtins.attrNames entry == ["archetypes" "roles"]) "${platform} must keep archetypes and roles as separate fields"
    && assertThat (builtins.all (choice: builtins.isString choice.label && builtins.isString choice.module) entry.archetypes) "${platform} archetype choices need labels and module paths"
    && assertThat validArchetypeLabels "${platform} archetype choices need non-empty labels and module paths"
    && assertThat (hasUnique archetypeModules) "${platform} contains a duplicate archetype module"
    && assertThat (hasUnique entry.roles) "${platform} contains a duplicate role"
    && assertThat correctlyScopedArchetypes "${platform} lists an archetype for the wrong operating system"
    && assertThat matchesReviewedArchetypeMatrix "${platform} archetypes differ from the reviewed platform/profile compatibility matrix"
    && assertThat existingArchetypes "${platform} references a missing archetype module"
    && assertThat importableArchetypes "${platform} references a path that is not an importable Nix module"
    && assertThat allRolesDefined "${platform} lists a role absent from the common module stack"
    && assertThat allListedRoleModulesExist "a listed role has no corresponding role module"
    && assertThat allListedRoleModulesAreImported "the common role module stack does not import every listed role module"
    && assertThat (lib.hasInfix "./common/options.nix" commonModuleText && lib.hasInfix "./roles" commonModuleText) "the common module entry point does not import the shared role definitions"
    && assertThat (builtins.all (role: builtins.isString role) entry.roles) "${platform} role choices must be role names";

  checks = map (platform: checkPlatform platform options.${platform}) expectedPlatforms;
  test =
    builtins.deepSeq checks
    (assertThat (builtins.attrNames options == expectedPlatforms) "supported platforms must be exactly the approved Darwin and Linux systems");
in
  pkgs.runCommand "test-machine-wizard-options" {} ''
    ${
      if test
      then "echo 'Machine wizard option manifest invariants passed'"
      else "exit 1"
    }
    touch $out
  ''
