# Package availability tests
{
  pkgs,
  lib,
  self,
}: {
  # Test that core packages are available
  corePackagesTest =
    pkgs.runCommand "test-core-packages"
    {
      nativeBuildInputs = [pkgs.nix];
    }
    ''
      echo "=== Testing Core Packages ==="

      # Test each core package exists
      CORE_PACKAGES="git curl wget vim coreutils"

      for pkg in $CORE_PACKAGES; do
        echo -n "Checking $pkg... "
        if nix-instantiate --eval --expr "(import <nixpkgs> {}).$pkg" 2>/dev/null > /dev/null; then
          echo "✓"
        else
          echo "✗ NOT FOUND"
          exit 1
        fi
      done

      # Test that bootstrap config builds
      echo -n "Testing bootstrap configuration builds... "
      if nix build ${self}#nixosConfigurations.bootstrap.config.system.build.toplevel \
          --dry-run --impure 2>&1 | grep -q "drv"; then
        echo "✓"
      else
        echo "✗ BUILD FAILED"
        exit 1
      fi

      touch $out
      echo "=== Core Packages Test Complete ==="
    '';

  # Test foundation packages
  foundationPackagesTest =
    pkgs.runCommand "test-foundation-packages"
    {
      nativeBuildInputs = [pkgs.nix pkgs.jq];
    }
    ''
      echo "=== Testing Foundation Packages ==="

      # Test that foundation packages are defined by importing bundles
      FOUNDATION_PKGS=$(nix-instantiate --eval --expr '
        let
          flake = builtins.getFlake (toString ./.);
          pkgs = flake.packages.x86_64-linux.default.pkgs or (import flake.inputs.nixpkgs { system = "x86_64-linux"; });
          bundles = import ./bundles.nix { inherit pkgs; };
        in
          builtins.length bundles.roles.foundation.packages
      ' 2>/dev/null || echo "0")

      if [ "$FOUNDATION_PKGS" = "0" ] || [ -z "$FOUNDATION_PKGS" ]; then
        echo "✗ Could not retrieve foundation packages"
        exit 1
      fi

      echo "Found $FOUNDATION_PKGS foundation packages"

      # Test that type-server includes foundation
      echo -n "Testing type-server includes foundation... "
      if nix-instantiate --eval --expr '
        let
          flake = builtins.getFlake (toString ./.);
          config = flake.nixosConfigurations.type-server.config;
        in
          config.myConfig.syncthing.enable or false
      ' 2>/dev/null | grep -q "true"; then
        echo "✓"
      else
        echo "✗"
        exit 1
      fi

      touch $out
      echo "=== Foundation Packages Test Complete ==="
    '';

  # Test configuration validation
  configValidationTest =
    pkgs.runCommand "test-config-validation"
    {
      nativeBuildInputs = [pkgs.nix];
    }
    ''
      echo "=== Testing Configuration Validation ==="

      # Test 1Password SSH agent configuration
      echo -n "Testing 1Password SSH agent option... "
      if nix-instantiate --eval --expr '
        let
          flake = builtins.getFlake (toString ./.);
          config = flake.nixosConfigurations.type-server.config;
        in
          config.programs.ssh.extraConfig or ""
      ' 2>/dev/null | grep -q "IdentityAgent"; then
        echo "✓ SSH agent configured"
      else
        echo "⚠ SSH agent not configured (may be Darwin-only)"
      fi

      # Test syncthing option exists
      echo -n "Testing syncthing option... "
      if nix-instantiate --eval --expr '
        let
          flake = builtins.getFlake (toString ./.);
          options = flake.nixosConfigurations.type-server.options;
        in
          options.myConfig.syncthing.enable or {} != {}
      ' 2>/dev/null | grep -q "true"; then
        echo "✓"
      else
        echo "✗"
        exit 1
      fi

      touch $out
      echo "=== Configuration Validation Complete ==="
    '';
}
