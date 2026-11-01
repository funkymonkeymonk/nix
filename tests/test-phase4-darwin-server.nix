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

    # Darwin server archetypes retain collectors but not local backends.
    ${
      if !(self.darwinConfigurations.darwin-server.config.myConfig.prometheus.enable or false)
      then ""
      else ''echo "FAIL: darwin-server must not enable Prometheus"; exit 1''
    }
    ${
      if !(self.darwinConfigurations.darwin-server.config.myConfig.alertmanager.enable or false)
      then ""
      else ''echo "FAIL: darwin-server must not enable Alertmanager"; exit 1''
    }
    ${
      if !(self.darwinConfigurations.darwin-server.config.myConfig.loki.enable or false)
      then ""
      else ''echo "FAIL: darwin-server must not enable Loki"; exit 1''
    }
    ${
      if !(self.darwinConfigurations.darwin-server.config.myConfig.grafana.enable or false)
      then ""
      else ''echo "FAIL: darwin-server must not enable Grafana"; exit 1''
    }
    ${
      if self.darwinConfigurations.darwin-server.config.myConfig.vector.enable
      then ""
      else ''echo "FAIL: darwin-server should retain Vector"; exit 1''
    }
    ${
      if self.darwinConfigurations.darwin-server.config.myConfig.collector.destinationHostname == "drlight"
      then ""
      else ''echo "FAIL: Darwin Vector should ship to drlight"; exit 1''
    }
    echo "  collector-only observability configuration: ✓"

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
          && megamanx.myConfig.pi.opencodeGoOnePasswordItem == "Opencode/Service Accounts/MegamanX"
          && megamanx.myConfig.pi.jevOnePasswordItem == "Opencode/Service Accounts/MegamanX"
          && megamanx.myConfig.pi.npmPackages."pi-jev" == "^0.7.0"
          && megamanx.myConfig.pi.settings.defaultProvider == "opencode-go"
          && megamanx.myConfig.pi.settings.defaultModel == "gpt-6-luna"
          && megamanx.home-manager.users.monkey.home.sessionVariables.PI_JEV_BASE_URL == "https://opencode.ai/inference/systemone"
          && megamanx.home-manager.users.monkey.home.sessionVariables.TYPESAFE_DEFAULT_MODEL == "jev-1.13"
          && megamanx.home-manager.users.monkey.programs.onepassword-secrets.secrets.pijevApiKey.reference == "op://Opnix/Opencode/Service Accounts/MegamanX"
          && megamanx.home-manager.users.monkey.programs.onepassword-secrets.secrets.pijevApiKey.path == ".pi/agent/secrets/typesafe_api_key"
          && builtins.elem "retrieveOpnixSecrets" megamanx.home-manager.users.monkey.home.activation.piOpenCodeGoAuth.after
          && megamanx.myConfig.pi.pluginsSource != null
          && megamanx.myConfig.zellij.enable
          && megamanx.myConfig.llmClient.serverPort == "8081"
          && megamanx.myConfig.omlx.enable
          && megamanx.myConfig.omlx.server.host == "0.0.0.0"
          && megamanx.myConfig.bifrost.enable
          && megamanx.myConfig.bifrost.host == "0.0.0.0"
          && !(megamanx.myConfig.prometheus.enable or false)
          && !(megamanx.launchd.daemons ? prometheus)
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

    ${
      let
        megamanx = self.darwinConfigurations.MegamanX.config;
        sshConfig = megamanx.environment.etc."ssh/sshd_config.d/100-nix-darwin.conf".text;
      in
        if
          megamanx.services.openssh.enable
          && megamanx.myConfig.onepassword.defaultVault == "Opnix"
          && megamanx.myConfig.onepassword.sudoPasswordRef == "op://Private/MegamanX Sudo Password/password"
          && !pkgs.lib.hasInfix "NOPASSWD" megamanx.security.sudo.extraConfig
          && pkgs.lib.hasInfix "PasswordAuthentication yes" sshConfig
          && !pkgs.lib.hasInfix "PasswordAuthentication no" sshConfig
          && builtins.hasAttr "caddy" megamanx.myConfig
          && megamanx.myConfig.caddy.enable
          && builtins.hasAttr "resolver/internal" megamanx.environment.etc
          && megamanx.environment.etc."resolver/internal".text == "nameserver 127.0.0.1\nport 5354\n"
          && builtins.hasAttr "dnsmasq" megamanx.launchd.user.agents
          && builtins.hasAttr "caddy" megamanx.launchd.user.agents
        then ""
        else ''echo "FAIL: MegamanX deployment must keep .internal DNS and password SSH available"; exit 1''
    }
    echo "  MegamanX: .internal resolver and password SSH remain enabled ✓"

    ${
      let
        darwinServer = self.darwinConfigurations.darwin-server.config;
        wweaver = self.darwinConfigurations.wweaver.config;
      in
        if
          builtins.hasAttr "ssh" darwinServer.myConfig
          && !darwinServer.myConfig.ssh.enable
          && !darwinServer.services.openssh.enable
          && builtins.hasAttr "ssh" wweaver.myConfig
          && !wweaver.myConfig.ssh.enable
          && !wweaver.services.openssh.enable
        then ""
        else ''echo "FAIL: Darwin SSH must default off and only be enabled by explicit host opt-in"; exit 1''
    }
    echo "  Darwin SSH: disabled by default; MegamanX opts in ✓"

    ${
      let
        wweaver = self.darwinConfigurations.wweaver.config;
      in
        if
          wweaver.myConfig.roles.pi.enable
          && wweaver.myConfig.pi.npmPackages."pi-jev" == "^0.7.0"
          && wweaver.myConfig.pi.jevOnePasswordItem == "Opencode/Service Accounts/wweaver"
          && wweaver.home-manager.users.wweaver.home.sessionVariables.PI_JEV_BASE_URL == "https://opencode.ai/inference/systemone"
          && wweaver.home-manager.users.wweaver.home.sessionVariables.TYPESAFE_DEFAULT_MODEL == "jev-1.13"
          && wweaver.home-manager.users.wweaver.programs.onepassword-secrets.secrets.pijevApiKey.reference == "op://Personal/Opencode/Service Accounts/wweaver"
        then ""
        else ''echo "FAIL: wweaver should receive pi-jev with its Console Jev key"; exit 1''
    }
    echo "  wweaver: pi-jev package and Jev service account configured ✓"

    echo ""
    echo "All darwin-server tests passed"
    touch $out
  '';
in {
  inherit phase4DarwinServerTest;
}
