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
        if
          !megamanx.myConfig.roles.developer.enable
          && !megamanx.myConfig.roles.desktop.enable
          && !megamanx.myConfig.roles.workstation.enable
          && !megamanx.myConfig.roles.entertainment.enable
          && !megamanx.myConfig.roles.homebrew.enable
          && !megamanx.myConfig.roles.developer.enable
          && !megamanx.myConfig.roles.opencode.enable
          && megamanx.myConfig.roles.pi.enable
          && megamanx.myConfig.zellij.enable
          && megamanx.myConfig.llmClient.serverPort == "8081"
          && megamanx.myConfig.omlx.enable
          && megamanx.myConfig.omlx.server.host == "0.0.0.0"
          && megamanx.myConfig.bifrost.enable
          && megamanx.myConfig.bifrost.host == "0.0.0.0"
          && megamanx.myConfig.prometheus.enable
          && megamanx.myConfig.nodeExporter.enable
          && megamanx.myConfig.searxng.enable
          && megamanx.myConfig.temporal.enable
          && megamanx.myConfig.temporal.ip == "0.0.0.0"
          && megamanx.myConfig.temporal.uiIp == "0.0.0.0"
          && pkgs.lib.hasInfix "ghostty-terminfo" megamanx.environment.variables.TERMINFO_DIRS
        then ""
        else ''echo "FAIL: MegamanX should be a minimal remotely accessible headless server"; exit 1''
    }
    echo "  MegamanX: minimal headless LLM server with remote Temporal ✓"

    echo ""
    echo "All darwin-server tests passed"
    touch $out
  '';
in {
  inherit phase4DarwinServerTest;
}
