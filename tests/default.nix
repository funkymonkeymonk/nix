# Nix-based Tests for Foundation
# These tests use nix eval and can run in CI
{pkgs, ...}: let
  # Test utilities
  testPackages = import ./test-packages.nix {inherit pkgs;};
  testRoles = import ./test-roles.nix {inherit pkgs;};
  testCoverage = import ./test-coverage.nix {inherit pkgs;};
in {
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

  # Coverage tracking
  module-coverage = testCoverage.moduleCoverageTest;
}
