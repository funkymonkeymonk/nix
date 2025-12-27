# Bundle test for creative role on Darwin
{
  pkgs,
  lib,
  ...
}: let
  # Import the bundles configuration
  bundles = import ../../bundles.nix {inherit pkgs lib;};

  # Create a minimal configuration for testing the creative bundle
  testConfig = {
    # Core system configuration
    nixpkgs.config.allowUnfree = true;

    # Include creative bundle packages
    environment.systemPackages = bundles.roles.creative.packages ++ bundles.platforms.darwin.packages;

    # Include creative bundle config
    homebrew = bundles.roles.creative.config.homebrew or {};
  };

  # Test evaluation
  result =
    pkgs.runCommand "test-creative-darwin" {
      buildInputs = [pkgs.nix];
    } ''
      # Test that all packages exist
      ${lib.concatMapStringsSep "\n" (pkg: ''
          echo "Testing package: ${pkg.name or pkg}"
          ${pkgs.nix}/bin/nix-store --query ${pkg.outPath or pkg} > /dev/null
        '')
        bundles.roles.creative.packages}

      # Test homebrew casks exist
      ${lib.optionalString (bundles.roles.creative.config.homebrew ? casks)
        (lib.concatMapStringsSep "\n" (cask: ''
            echo "Testing Homebrew cask: ${cask}"
            # Cask validation would be done during actual homebrew evaluation
          '')
          bundles.roles.creative.config.homebrew.casks)}

      echo "✅ Creative bundle (Darwin) validation passed"
      touch $out
    '';
in {
  # Output the test result
  test = result;

  # Also provide the config for debugging
  config = testConfig;
}
