{
  pkgs,
  self,
  ...
}: let
  hasConfig = name: builtins.hasAttr name self.darwinConfigurations;

  phase4DarwinServerTest = pkgs.runCommand "test-phase4-darwin-server" {} ''
    echo "=== Testing Phase 4 Darwin Server v2 Config ==="
    echo ""

    # Test darwin-server-v2 config exists
    ${
      if hasConfig "darwin-server-v2"
      then ""
      else ''echo "FAIL: darwin-server-v2 not found"; exit 1''
    }
    echo "  darwin-server-v2: defined ✓"

    # Test old darwin-server config still exists
    ${
      if hasConfig "darwin-server"
      then ""
      else ''echo "FAIL: darwin-server not found"; exit 1''
    }
    echo "  darwin-server: preserved ✓"

    echo ""
    echo "All Phase 4 darwin-server tests passed"
    touch $out
  '';
in {
  inherit phase4DarwinServerTest;
}
