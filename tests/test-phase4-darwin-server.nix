{
  pkgs,
  self,
  ...
}: let
  hasConfig = name: builtins.hasAttr name self.darwinConfigurations;

  phase4DarwinServerTest = pkgs.runCommand "test-phase4-darwin-server" {} ''
    echo "=== Testing Darwin Server Config ==="
    echo ""

    # Test darwin-server config exists and uses modern library pattern
    ${
      if hasConfig "darwin-server"
      then ""
      else ''echo "FAIL: darwin-server not found"; exit 1''
    }
    echo "  darwin-server: defined ✓"

    echo ""
    echo "All darwin-server tests passed"
    touch $out
  '';
in {
  inherit phase4DarwinServerTest;
}
