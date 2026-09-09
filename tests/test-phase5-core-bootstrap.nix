{
  pkgs,
  self,
  ...
}: let
  hasNixosConfig = name: builtins.hasAttr name self.nixosConfigurations;
  flakeText = builtins.readFile ../flake.nix;

  coreBootstrapTest = pkgs.runCommand "test-core-bootstrap" {} ''
    echo "=== Testing Bootstrap Config ==="
    echo ""

    # Test bootstrap config exists
    ${
      if hasNixosConfig "bootstrap"
      then ""
      else ''echo "FAIL: bootstrap not found"; exit 1''
    }
    echo "  bootstrap: defined ✓"

    ${
      if builtins.pathExists ../library/machines/bootstrap.nix
      then ''echo "  bootstrap machine module: defined ✓"''
      else ''echo "FAIL: bootstrap machine module not found"; exit 1''
    }

    ${
      if builtins.pathExists ../library/machines/installer-iso.nix
      then ''echo "  installer-iso machine module: defined ✓"''
      else ''echo "FAIL: installer-iso machine module not found"; exit 1''
    }

    ${
      if pkgs.lib.hasInfix "./library/machines/bootstrap.nix" flakeText
      then ""
      else ''echo "FAIL: bootstrap machine module not imported by flake.nix"; exit 1''
    }

    ${
      if pkgs.lib.hasInfix "./library/machines/installer-iso.nix" flakeText
      then ""
      else ''echo "FAIL: installer-iso machine module not imported by flake.nix"; exit 1''
    }

    echo ""
    echo "All bootstrap tests passed"
    touch $out
  '';
in {
  inherit coreBootstrapTest;
}
