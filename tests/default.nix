# Nix-based Tests for Foundation
# These tests use nix eval and can run in CI
{
  pkgs,
  lib,
  self,
  ...
}: let
  # Test utilities
  testOptions = import ./test-options.nix {inherit pkgs lib;};
  testPackages = import ./test-packages.nix {inherit pkgs lib self;};
in {
  # Option validation tests
  foundation-options = testOptions.runFoundationOptionTests;

  # Package availability tests
  core-packages = testPackages.corePackagesTest;
  foundation-packages = testPackages.foundationPackagesTest;

  # Configuration validation tests
  config-validation = testPackages.configValidationTest;
}
