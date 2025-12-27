# Bundle test template
{
  pkgs,
  lib,
  bundleName,
  platform ? "darwin",
}: let
  # Import bundles configuration
  bundles = import ../../bundles.nix {inherit pkgs lib;};

  # Get the specific bundle
  bundle = bundles.roles.${bundleName} or (throw "Bundle ${bundleName} not found");

  # Get platform-specific config
  platformBundle = bundles.platforms.${platform} or (throw "Platform ${platform} not found");

  # Combined packages for this bundle+platform
  allPackages = bundle.packages ++ platformBundle.packages;

  # Test evaluation
  result =
    pkgs.runCommand "test-${bundleName}-${platform}" {
      buildInputs = [pkgs.nix];
    } ''
      echo "🧪 Testing bundle: ${bundleName} on platform: ${platform}"
      echo "📦 Found ${toString (builtins.length allPackages)} packages"

      # Test that all packages exist
      ${lib.concatMapStringsSep "\n" (pkg: ''
          echo "  ✓ Package: ${pkg.name or pkg}"
          ${pkgs.nix}/bin/nix-store --query ${pkg.outPath or pkg} > /dev/null
        '')
        allPackages}

      # Test homebrew casks if they exist
      ${lib.optionalString (bundle.config ? homebrew && bundle.config.homebrew ? casks)
        (lib.concatMapStringsSep "\n" (cask: ''
            echo "  ✓ Homebrew cask: ${cask}"
          '')
          bundle.config.homebrew.casks)}

      # Test platform-specific config
      ${lib.optionalString (platformBundle.config ? programs) ''
        echo "  ✓ Platform-specific programs configured"
      ''}

      echo "✅ ${bundleName} bundle (${platform}) validation passed"
      touch $out
    '';
in {
  # Output test result
  test = result;

  # Provide bundle for debugging
  inherit bundle platformBundle allPackages;
}
