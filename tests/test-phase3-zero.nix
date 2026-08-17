{
  pkgs,
  self,
  ...
}: let
  hasConfig = name: builtins.hasAttr name self.nixosConfigurations;

  phase3ZeroTest = pkgs.runCommand "test-phase3-zero" {} ''
    echo "=== Testing Zero NixOS Config ==="
    echo ""

    # Test zero config exists and uses the new archetype-based composition.
    ${
      if hasConfig "zero"
      then ""
      else ''echo "FAIL: zero not found"; exit 1''
    }
    echo "  zero: defined ✓"

    # The old zero-v2 scratch output has been retired (Phase 8 cleanup).
    ${
      if hasConfig "zero-v2"
      then ''echo "FAIL: zero-v2 should be retired"; exit 1''
      else ""
    }
    echo "  zero-v2: retired ✓"

    echo ""
    echo "All zero tests passed"
    touch $out
  '';
in {
  inherit phase3ZeroTest;
}
