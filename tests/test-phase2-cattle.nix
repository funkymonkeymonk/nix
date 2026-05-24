{
  pkgs,
  self,
  ...
}: let
  hasConfig = name: builtins.hasAttr name self.nixosConfigurations;

  phase2CattleTest = pkgs.runCommand "test-phase2-cattle" {} ''
    echo "=== Testing Phase 2 Cattle NixOS Configs ==="
    echo ""

    # Test v2 configs exist
    ${
      if hasConfig "type-server-v2"
      then ""
      else ''echo "FAIL: type-server-v2 not found"; exit 1''
    }
    echo "  type-server-v2: defined ✓"

    ${
      if hasConfig "type-server-arm-v2"
      then ""
      else ''echo "FAIL: type-server-arm-v2 not found"; exit 1''
    }
    echo "  type-server-arm-v2: defined ✓"

    ${
      if hasConfig "type-desktop-v2"
      then ""
      else ''echo "FAIL: type-desktop-v2 not found"; exit 1''
    }
    echo "  type-desktop-v2: defined ✓"

    # Test old configs still exist
    ${
      if hasConfig "type-server"
      then ""
      else ''echo "FAIL: type-server not found"; exit 1''
    }
    echo "  type-server: preserved ✓"

    ${
      if hasConfig "type-server-arm"
      then ""
      else ''echo "FAIL: type-server-arm not found"; exit 1''
    }
    echo "  type-server-arm: preserved ✓"

    echo ""
    echo "All Phase 2 cattle tests passed"
    touch $out
  '';
in {
  inherit phase2CattleTest;
}
