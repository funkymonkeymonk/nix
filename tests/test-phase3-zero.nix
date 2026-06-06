{
  pkgs,
  self,
  ...
}: let
  hasConfig = name: builtins.hasAttr name self.nixosConfigurations;

  phase3ZeroTest = pkgs.runCommand "test-phase3-zero" {} ''
    echo "=== Testing Phase 3 Zero NixOS v2 Config ==="
    echo ""

    # Test zero-v2 config exists
    ${
      if hasConfig "zero-v2"
      then ""
      else ''echo "FAIL: zero-v2 not found"; exit 1''
    }
    echo "  zero-v2: defined ✓"

    # Test old zero config still exists
    ${
      if hasConfig "zero"
      then ""
      else ''echo "FAIL: zero not found"; exit 1''
    }
    echo "  zero: preserved ✓"

    echo ""
    echo "All Phase 3 zero tests passed"
    touch $out
  '';
in {
  inherit phase3ZeroTest;
}
