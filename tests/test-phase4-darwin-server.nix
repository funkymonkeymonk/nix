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

    ${
      if hasConfig "wweaver" && hasConfig "MegamanX"
      then ""
      else ''echo "FAIL: Darwin machine configurations should be exposed by flake-parts modules"; exit 1''
    }
    echo "  Darwin machine targets: defined ✓"

    # The generic type target was redundant with the shared server archetype.
    ${
      if !hasConfig "type-darwin-server"
      then ""
      else ''echo "FAIL: redundant type-darwin-server should be removed"; exit 1''
    }
    echo "  type-darwin-server: removed ✓"

    # The server archetype owns the local observability stack.
    ${
      if self.darwinConfigurations.darwin-server.config.myConfig.loki.enable
      then ""
      else ''echo "FAIL: darwin-server should enable Loki"; exit 1''
    }
    ${
      if self.darwinConfigurations.darwin-server.config.myConfig.vector.enable
      then ""
      else ''echo "FAIL: darwin-server should enable Vector"; exit 1''
    }
    ${
      if self.darwinConfigurations.darwin-server.config.myConfig.grafana.enable
      then ""
      else ''echo "FAIL: darwin-server should enable Grafana"; exit 1''
    }
    echo "  observability stack enabled: ✓"

    ${
      let
        megamanx = self.darwinConfigurations.MegamanX.config;
      in
        if !(builtins.hasAttr "temporal" megamanx.myConfig)
        then ""
        else ''echo "FAIL: MegamanX should not configure Temporal"; exit 1''
    }
    echo "  MegamanX: Temporal removed ✓"

    echo ""
    echo "All darwin-server tests passed"
    touch $out
  '';
in {
  inherit phase4DarwinServerTest;
}
