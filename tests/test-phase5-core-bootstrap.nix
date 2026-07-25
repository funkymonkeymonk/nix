{
  pkgs,
  self,
  ...
}: let
  hasNixosConfig = name: builtins.hasAttr name self.nixosConfigurations;

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

    echo ""
    echo "All bootstrap tests passed"
    touch $out
  '';
in {
  inherit coreBootstrapTest;
}
