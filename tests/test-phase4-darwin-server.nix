{
  pkgs,
  self,
  inputs,
  ...
}: let
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  inferenceArchetypeSource = builtins.readFile ../library/archetypes/headless-inference-darwin.nix;
  vmManagementArchetypeSource = builtins.readFile ../library/archetypes/vm-management-darwin.nix;
  hasConfig = name: builtins.hasAttr name self.darwinConfigurations;
  hasCatalogModule = suffix: machine:
    pkgs.lib.any
    (module:
      (builtins.isPath module || builtins.isString module)
      && pkgs.lib.hasSuffix suffix (builtins.toString module))
    machine.modules;

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
      if
        hasCatalogModule "/archetypes/vm-management-darwin.nix" catalog.darwin-server
        && !hasCatalogModule "/hosts/darwin-server" catalog.darwin-server
        && !hasCatalogModule "/machines/darwin-server" catalog.darwin-server
        && hasCatalogModule "/archetypes/headless-inference-darwin.nix" catalog.MegamanX
        && !hasCatalogModule "/hosts/megamanx" catalog.MegamanX
        && !hasCatalogModule "/machines/megamanx" catalog.MegamanX
        && pkgs.lib.hasInfix "./base-darwin.nix" inferenceArchetypeSource
        && pkgs.lib.hasInfix "./base-darwin.nix" vmManagementArchetypeSource
        && pkgs.lib.hasInfix "./server-observability-darwin.nix" inferenceArchetypeSource
        && pkgs.lib.hasInfix "./server-observability-darwin.nix" vmManagementArchetypeSource
        && !builtins.pathExists ../hosts/darwin-server
        && !builtins.pathExists ../hosts/megamanx
        && !builtins.pathExists ../machines/darwin-server
        && !builtins.pathExists ../machines/megamanx
      then ""
      else ''echo "FAIL: Darwin servers must be composed from catalog archetypes without host directories"; exit 1''
    }
    echo "  Darwin servers use catalog archetypes without host directories ✓"

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
      if !(self.darwinConfigurations.darwin-server.config.launchd.daemons ? grafana)
      then ""
      else ''echo "FAIL: darwin-server must not configure a Grafana launchd service"; exit 1''
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
          && megamanx.myConfig.pi.opencodeGoOnePasswordItem == "OpenCode Service Account - MegamanX/credential"
          && megamanx.myConfig.pi.jevOnePasswordItem == "OpenCode Service Account - MegamanX/credential"
          && megamanx.myConfig.pi.npmPackages."pi-jev" == "^0.7.0"
          && megamanx.myConfig.pi.settings.defaultProvider == "opencode-go"
          && megamanx.myConfig.pi.settings.defaultModel == "gpt-6-luna"
          && megamanx.home-manager.users.monkey.home.sessionVariables.PI_JEV_BASE_URL == "https://opencode.ai/inference/systemone"
          && megamanx.home-manager.users.monkey.home.sessionVariables.TYPESAFE_DEFAULT_MODEL == "jev-1.13"
          && megamanx.home-manager.users.monkey.programs.onepassword-secrets.secrets.pijevApiKey.reference == "op://Opnix/OpenCode Service Account - MegamanX/credential"
          && megamanx.home-manager.users.monkey.programs.onepassword-secrets.secrets.pijevApiKey.path == ".pi/agent/secrets/typesafe_api_key"
          && builtins.elem "retrieveOpnixSecrets" megamanx.home-manager.users.monkey.home.activation.piOpenCodeGoAuth.after
          && megamanx.myConfig.pi.pluginsSource != null
          && megamanx.myConfig.zellij.enable
          && megamanx.myConfig.llmClient.serverPort == "8081"
          && megamanx.myConfig.omlx.enable
          && megamanx.myConfig.omlx.server.host == "127.0.0.1"
          && megamanx.myConfig.omlx.maxConcurrentRequests == 4
          && megamanx.launchd.daemons ? omlx
          && !(megamanx.launchd.user.agents ? omlx)
          && megamanx.services.tailscale.enable
          && megamanx.launchd.daemons ? tailscaled
          && megamanx.launchd.daemons.tailscaled.serviceConfig.KeepAlive
          && (megamanx.myConfig.nodeExporter.listenOnTailscale or false)
          && (megamanx.myConfig.vector.enable or false)
          && megamanx.myConfig.collector.destinationHostname == "drlight"
          && (megamanx.myConfig.vector.hostLabel or "") == "MegamanX"
          && builtins.elem "/Users/monkey/Library/Logs/omlx/*.log" (megamanx.myConfig.vector.logGlobs or [])
          && megamanx.myConfig.bifrost.enable
          && megamanx.myConfig.bifrost.host == "127.0.0.1"
          && (megamanx.myConfig.bifrost.exposeViaTailscaleServe or false)
          && megamanx.launchd.daemons ? bifrost-tailscale-serve
          && !(megamanx.myConfig.prometheus.enable or false)
          && !(megamanx.launchd.daemons ? prometheus)
          && megamanx.myConfig.nodeExporter.enable
          && megamanx.myConfig.searxng.enable
          && !(megamanx.myConfig.lume.enable or false)
          && megamanx.system.stateVersion == 4
          && megamanx.system.primaryUser == "monkey"
          && !(megamanx.myConfig.temporal.enable or false)
          && !(megamanx.launchd.daemons ? temporal)
          && !(builtins.elem pkgs.temporal-cli megamanx.environment.systemPackages)
          && pkgs.lib.hasInfix "ghostty-terminfo" megamanx.environment.variables.TERMINFO_DIRS
        then ""
        else ''echo "FAIL: MegamanX should be a minimal remotely accessible headless server"; exit 1''
    }
    echo "  MegamanX: headless inference server without Temporal ✓"

    ${
      let
        megamanx = self.darwinConfigurations.MegamanX.config;
        sshConfig = megamanx.environment.etc."ssh/sshd_config.d/100-nix-darwin.conf".text;
      in
        if
          megamanx.services.openssh.enable
          && builtins.elem "nixbuilder" megamanx.nix.settings.trusted-users
          && megamanx.users.users.nixbuilder.isHidden
          && megamanx.users.users.nixbuilder.openssh.authorizedKeys.keys != []
          && megamanx.myConfig.onepassword.defaultVault == "Opnix"
          && megamanx.myConfig.onepassword.sudoPasswordRef == "op://Private/MegamanX Sudo Password/password"
          && !pkgs.lib.hasInfix "NOPASSWD" megamanx.security.sudo.extraConfig
          && pkgs.lib.hasInfix "PasswordAuthentication yes" sshConfig
          && pkgs.lib.hasInfix "Match User nixbuilder" sshConfig
          && pkgs.lib.hasInfix "AuthenticationMethods publickey" sshConfig
          && pkgs.lib.hasInfix "PasswordAuthentication no" sshConfig
          && pkgs.lib.hasInfix "KbdInteractiveAuthentication no" sshConfig
          && pkgs.lib.hasInfix "Match all" sshConfig
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
          && darwinServer.myConfig.lume.enable
          && darwinServer.myConfig.lume.enableBackgroundService
          && darwinServer.myConfig.lume.enableAutoUpdater
          && builtins.elem "macos-tahoe-vanilla:latest" darwinServer.myConfig.lume.prePullImages
          && darwinServer.launchd.daemons ? lume
          && darwinServer.myConfig.roles.developer.enable
          && darwinServer.myConfig.roles.opencode.enable
          && darwinServer.system.stateVersion == 4
          && darwinServer.system.primaryUser == "monkey"
          && !(darwinServer.myConfig.omlx.enable or false)
          && !(darwinServer.myConfig.bifrost.enable or false)
          && !(darwinServer.myConfig.searxng.enable or false)
          && !(darwinServer.myConfig.caddy.enable or false)
          && pkgs.lib.hasInfix "monkey ALL=(ALL) NOPASSWD: ALL" darwinServer.security.sudo.extraConfig
          && darwinServer.time.timeZone == "America/New_York"
          && builtins.hasAttr "newsyslog.d/lume-services.conf" darwinServer.environment.etc
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
          && wweaver.myConfig.onepassword.defaultVault == "Opnix"
          && wweaver.myConfig.onepassword.sudoPasswordRef == "op://Employee/wweaver Sudo Password/password"
          && wweaver.myConfig.pi.jevOnePasswordItem == "Opencode/Service Accounts/wweaver"
          && wweaver.home-manager.users.wweaver.home.sessionVariables.PI_JEV_BASE_URL == "https://opencode.ai/inference/systemone"
          && wweaver.home-manager.users.wweaver.home.sessionVariables.TYPESAFE_DEFAULT_MODEL == "jev-1.13"
          && wweaver.home-manager.users.wweaver.programs.onepassword-secrets.secrets.pijevApiKey.reference == "op://Opnix/Opencode/Service Accounts/wweaver"
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
