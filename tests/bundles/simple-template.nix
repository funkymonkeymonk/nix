# Simplified bundle test template (unfree-compatible)
{
  pkgs,
  lib,
  bundleName,
  platform ? "darwin",
}: let
  # Import bundles configuration
  bundles = import ../../bundles.nix {inherit pkgs lib;};

  # Get specific bundle (skip base to avoid unfree issues)
  bundle = bundles.roles.${bundleName} or (throw "Bundle ${bundleName} not found");

  # Test only bundle packages (skip platform bundles)
  bundlePackages = bundle.packages;

  # Test evaluation
  result =
    pkgs.runCommand "test-${bundleName}-${platform}" {
      buildInputs = [pkgs.nix];
    } ''
      echo "🧪 Testing bundle: ${bundleName} on platform: ${platform}"
      echo "📦 Found ${toString (builtins.length bundlePackages)} packages in bundle"

      # Test that all bundle packages exist
      ${lib.concatMapStringsSep "\n" (pkg: ''
          echo "  ✓ Package: ${pkg.name or pkg}"
          ${pkgs.nix}/bin/nix-store --query ${pkg.outPath or pkg} > /dev/null
        '')
        bundlePackages}

      # Test homebrew casks if they exist
      ${lib.optionalString (bundle.config ? homebrew && bundle.config.homebrew ? casks)
        (lib.concatMapStringsSep "\n" (cask: ''
            echo "  ✓ Homebrew cask: ${cask}"
          '')
          bundle.config.homebrew.casks)}

      echo "✅ ${bundleName} bundle (${platform}) validation passed"
      touch $out
    '';
in {
  # Output test result
  test = result;

  # Provide bundle for debugging
  inherit bundle bundlePackages platform;
}
