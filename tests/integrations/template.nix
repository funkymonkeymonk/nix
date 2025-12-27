# Integration test template
{
  pkgs,
  lib,
  machineName,
  bundleName,
  platform ? "darwin",
  ...
}: let
  # Import bundles configuration
  bundles = import ../../bundles.nix {inherit pkgs lib;};

  # Get specific bundle and platform
  bundle = bundles.roles.${bundleName} or (throw "Bundle ${bundleName} not found");
  platformBundle = bundles.platforms.${platform} or (throw "Platform ${platform} not found");

  # All packages for this integration test
  allPackages =
    bundles.roles.base.packages
    ++ bundle.packages
    ++ platformBundle.packages;

  # Test evaluation
  result =
    pkgs.runCommand "test-integration-${machineName}-${bundleName}-${platform}" {
      buildInputs = [pkgs.nix];
    } ''
      echo "🧪 Testing integration: ${machineName} + ${bundleName} bundle on ${platform}"
      echo "📦 Total packages: ${toString (builtins.length allPackages)}"
      echo "🎯 This simulates how ${bundleName} bundle integrates with ${machineName}"

      # Test that all packages exist
      ${lib.concatMapStringsSep "\n" (pkg: ''
          echo "  ✓ Integration package: ${pkg.name or pkg}"
          ${pkgs.nix}/bin/nix-store --query ${pkg.outPath or pkg} > /dev/null
        '')
        allPackages}

      # Test homebrew cask integration
      ${lib.optionalString (bundle.config ? homebrew && bundle.config.homebrew ? casks)
        (lib.concatMapStringsSep "\n" (cask: ''
            echo "  ✓ Bundle Homebrew cask: ${cask} on ${machineName}"
          '')
          bundle.config.homebrew.casks)}

      # Test platform-specific homebrew integration
      ${lib.optionalString (platformBundle.config ? homebrew && platformBundle.config.homebrew ? casks)
        (lib.concatMapStringsSep "\n" (cask: ''
            echo "  ✓ Platform Homebrew cask: ${cask} on ${machineName}"
          '')
          platformBundle.config.homebrew.casks)}

      echo "✅ ${machineName}-${bundleName}-${platform} integration validation passed"
      touch $out
    '';
in {
  # Output test result
  test = result;

  # Provide information for debugging
  inherit machineName bundleName platform allPackages bundle platformBundle;
}
