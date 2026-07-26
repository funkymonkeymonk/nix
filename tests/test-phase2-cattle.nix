{
  pkgs,
  self,
  ...
}: let
  hasConfig = name: builtins.hasAttr name self.nixosConfigurations;

  phase2CattleTest = pkgs.runCommand "test-phase2-cattle" {} ''
    echo "=== Testing Cattle NixOS Configs ==="
    echo ""

    # type-server, type-server-arm, and type-desktop all use libraryLib.mkNixosSystem
    # directly now (no more -v2 twins — retired after parity verification)
    ${
      if hasConfig "type-server"
      then ""
      else ''echo "FAIL: type-server not found"; exit 1''
    }
    echo "  type-server: defined ✓"

    ${
      if hasConfig "type-server-arm"
      then ""
      else ''echo "FAIL: type-server-arm not found"; exit 1''
    }
    echo "  type-server-arm: defined ✓"

    ${
      if hasConfig "type-desktop"
      then ""
      else ''echo "FAIL: type-desktop not found"; exit 1''
    }
    echo "  type-desktop: defined ✓"

    echo ""
    echo "All cattle tests passed"
    touch $out
  '';
in {
  inherit phase2CattleTest;
}
