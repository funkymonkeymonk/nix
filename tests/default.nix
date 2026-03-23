# Nix-based Tests for Foundation
# These tests use nix eval and can run in CI
{pkgs, ...}: let
  # Test utilities
  testPackages = import ./test-packages.nix {inherit pkgs;};
in {
  # Package availability tests
  core-packages = testPackages.corePackagesTest;
  foundation-packages = testPackages.foundationPackagesTest;

  # Configuration validation tests
  config-validation = testPackages.configValidationTest;

  # Option validation tests
  foundation-options = testPackages.foundationOptionsTest;

  # NixOS configuration tests (validates modules can be imported)
  nixos-configs = testPackages.nixosConfigsTest;
}
