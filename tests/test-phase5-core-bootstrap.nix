{
  pkgs,
  self,
  ...
}: let
  hasDarwinConfig = name: builtins.hasAttr name self.darwinConfigurations;
  hasNixosConfig = name: builtins.hasAttr name self.nixosConfigurations;

  coreBootstrapTest = pkgs.runCommand "test-core-bootstrap" {} ''
    echo "=== Testing Core and Bootstrap v2 Configs ==="
    echo ""

    # Test core-v2 exists
    ${
      if hasDarwinConfig "core-v2"
      then ""
      else ''echo "FAIL: core-v2 not found"; exit 1''
    }
    echo "  core-v2: defined ✓"

    # Test bootstrap-v2 exists
    ${
      if hasNixosConfig "bootstrap-v2"
      then ""
      else ''echo "FAIL: bootstrap-v2 not found"; exit 1''
    }
    echo "  bootstrap-v2: defined ✓"

    # Test old bootstrap unchanged
    ${
      if hasNixosConfig "bootstrap"
      then ""
      else ''echo "FAIL: bootstrap not found"; exit 1''
    }
    echo "  bootstrap: preserved ✓"

    echo ""
    echo "All core and bootstrap tests passed"
    touch $out
  '';
in {
  inherit coreBootstrapTest;
}
