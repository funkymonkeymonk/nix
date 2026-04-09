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

    # 1Password tests
    onepassword-options = testPackages.onepasswordOptionsTest;
    onepassword-config = testPackages.onepasswordConfigOutputTest;
    onepassword-opnix-guard = testPackages.onepasswordOpnixGuardTest;

    # Per-role tests
    role-evaluation = testRoles.roleEvaluationTest;
    role-composition = testRoles.allRolesCompositionTest;
    role-packages = testRoles.rolePackageInclusionTest;
    role-cascades = testRoles.roleCascadeTest;

    # Skills tests
    skills-manifest = testSkills.manifestValidationTest;
    skills-autoload-filtering = testSkills.autoLoadFilteringTest;
    skills-autoload-content = testSkills.autoLoadContentTest;
    skills-role-filtering = testSkills.roleFilteringTest;

    # Coverage tracking
    module-coverage = testCoverage.moduleCoverageTest;
  }
  // vmTests
