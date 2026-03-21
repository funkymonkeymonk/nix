# Test foundation options are properly defined
{pkgs, ...}: {
  runFoundationOptionTests =
    pkgs.runCommand "foundation-option-tests"
    {
      buildInputs = [pkgs.nix];
    }
    ''
      echo "Testing foundation options..."

      # Test 1: Core option exists
      if ${pkgs.nix}/bin/nix-instantiate --eval --expr '
        let
          flake = builtins.getFlake (toString ./.);
          options = flake.nixosConfigurations.bootstrap.options;
        in
          options.myConfig.enable or false
      ' 2>/dev/null | grep -q "true"; then
        echo "✓ Core options accessible"
      else
        echo "✗ Core options not accessible"
        exit 1
      fi

      # Test 2: Foundation packages defined
      if ${pkgs.nix}/bin/nix-instantiate --eval --expr '
        let
          flake = builtins.getFlake (toString ./.);
          pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
          bundles = import ./bundles.nix { inherit pkgs; };
        in
          builtins.length bundles.roles.foundation.packages > 0
      ' 2>/dev/null | grep -q "true"; then
        echo "✓ Foundation packages defined"
      else
        echo "✗ Foundation packages not defined"
        exit 1
      fi

      touch $out
      echo "All option tests passed!"
    '';
}
