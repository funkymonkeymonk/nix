# Nix-based Tests for Foundation
# These tests use nix eval and can run in CI
{
  pkgs,
  self ? null,
  ...
}: let
  # Test utilities
  testPackages = import ./test-packages.nix {inherit pkgs;};
  testRoles = import ./test-roles.nix {inherit pkgs;};
  testCoverage = import ./test-coverage.nix {inherit pkgs;};
  testSkills = import ./test-skills.nix {inherit pkgs;};
  testEmail = import ./test-email.nix {inherit pkgs;};
  testSketchybar = import ./test-sketchybar.nix {inherit pkgs;};
  testServices = import ./test-services.nix {inherit pkgs;};
  testHomeManager = import ./test-home-manager.nix {inherit pkgs;};
  testWorkspaceSwitch = import ./test-workspace-switch.nix {inherit pkgs;};

  # VM tests only available on x86_64-linux (NixOS testing framework)
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  vmTests =
    if isLinux && self != null
    then import ./vm {inherit pkgs self;}
    else {};
in
  {
    # Package availability tests
    core-packages = testPackages.corePackagesTest;
    foundation-packages = testPackages.foundationPackagesTest;

    # Configuration validation tests
    config-validation = testPackages.configValidationTest;

    # Option validation tests
    foundation-options = testPackages.foundationOptionsTest;

    # Per-role tests
    role-evaluation = testRoles.roleEvaluationTest;
    role-composition = testRoles.allRolesCompositionTest;
    role-packages = testRoles.rolePackageInclusionTest;
    role-cascades = testRoles.roleCascadeTest;
    llm-host-shared-models = testRoles.llmHostSharedModelsTest;

    # Skills tests
    skills-manifest = testSkills.manifestValidationTest;
    skills-autoload-filtering = testSkills.autoLoadFilteringTest;
    skills-autoload-content = testSkills.autoLoadContentTest;
    skills-role-filtering = testSkills.roleFilteringTest;
    skills-external-identification = testSkills.externalSkillsIdentificationTest;
    skills-external-command-generation = testSkills.externalSkillCommandGenerationTest;
    skills-external-empty-case = testSkills.externalSkillsEmptyTest;

    # Coverage tracking
    module-coverage = testCoverage.moduleCoverageTest;

    # Email module tests
    email-agent-options = testEmail.emailAgentOptionsTest;
    email-backup-options = testEmail.emailBackupOptionsTest;
    email-custom-options = testEmail.emailCustomOptionsTest;
    email-composition = testEmail.emailCompositionTest;
    email-backup-scripts = testEmail.emailBackupScriptsTest;
    email-separation = testEmail.emailSeparationTest;

    # 1Password guard and config output tests
    onepassword-guard = testPackages.onepasswordGuardTest;
    onepassword-config-output = testPackages.onepasswordConfigOutputTest;

    # Sketchybar tests
    sketchybar-options = testSketchybar.sketchybarOptionsTest;
    sketchybar-custom-options = testSketchybar.sketchybarCustomOptionsTest;
    sketchybar-theme = testSketchybar.sketchybarThemeTest;
    sketchybar-color-conversion = testSketchybar.sketchybarColorConversionTest;
    sketchybar-platform-guard = testSketchybar.sketchybarPlatformGuardTest;
    sketchybar-entrypoint = testSketchybar.sketchybarEntryPointTest;

    # Service module tests
    ollama-options = testServices.ollamaOptionsTest;
    ollama-custom-options = testServices.ollamaCustomOptionsTest;
    vane-options = testServices.vaneOptionsTest;
    vane-custom-options = testServices.vaneCustomOptionsTest;
    openclaw-options = testServices.openclawOptionsTest;
    vane-darwin-autostart-default = testServices.vaneDarwinAutoStartDefaultTest;
    vane-darwin-autostart-true = testServices.vaneDarwinAutoStartTrueTest;

    # Home-manager module tests
    jj-autosync-options = testHomeManager.jjAutosyncOptionsTest;
    jj-autosync-custom-options = testHomeManager.jjAutosyncCustomOptionsTest;
    opencode-options = testHomeManager.opencodeOptionsTest;
    opencode-custom-options = testHomeManager.opencodeCustomOptionsTest;
    shell-aliases = testHomeManager.shellAliasesTest;

    # Workspace-aware switch shell function tests
    workspace-switch = testWorkspaceSwitch.workspaceSwitchTest;
    fjj-options = testHomeManager.fjjOptionsTest;
    fjj-custom-options = testHomeManager.fjjCustomOptionsTest;

    # Aerospace option tests
    aerospace-options = testHomeManager.aerospaceOptionsTest;
    aerospace-custom-options = testHomeManager.aerospaceCustomOptionsTest;
  }
  // vmTests
