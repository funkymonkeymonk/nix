# Caddy reverse proxy + dnsmasq DNS resolver for Darwin (macOS)
# Runs as a user agent (launchd.user.agents) for persistent local dev DNS names.
# dnsmasq resolves *.internal → 127.0.0.1
# Caddy routes *.internal hostnames to local services on port 80 with admin API on 2019.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.caddy;
  searxngCfg = config.myConfig.searxng;
  bifrostCfg = config.myConfig.bifrost;
  vaneCfg = config.myConfig.vane;

  commonLib = import ../../common/lib.nix {inherit lib;};

  darwinHomeDir = commonLib.darwinHomeDir config;

  mkServiceRegistry = commonLib.mkServiceRegistry;

  dnsPort = 5353;

  serviceRoutes =
    []
    ++ lib.optional (searxngCfg.enable && searxngCfg.port != cfg.port) {
      host = "searxng.internal";
      upstream = "localhost:${toString searxngCfg.port}";
    }
    ++ lib.optional (bifrostCfg.enable && bifrostCfg.port != cfg.port) {
      host = "bifrost.internal";
      upstream = "localhost:${toString bifrostCfg.port}";
    }
    ++ lib.optional (vaneCfg.enable && vaneCfg.port != cfg.port) {
      host = "vane.internal";
      upstream = "localhost:${toString vaneCfg.port}";
    };

  allRoutes = serviceRoutes ++ (lib.mapAttrsToList (host: upstream: {inherit host upstream;}) cfg.hosts);

  routeBlock = route: ''
    http://${route.host} {
      reverse_proxy ${route.upstream}
    }
  '';

  caddyfile = pkgs.writeText "Caddyfile" ''
    {
      auto_https off
      http_port ${toString cfg.port}
      admin localhost:2019
    }

    ${lib.concatMapStrings routeBlock allRoutes}
  '';

  caddyScript = pkgs.writeShellScript "caddy-launchd-service" ''
    set -euo pipefail
    export HOME="${darwinHomeDir}"
    export XDG_DATA_HOME="${cfg.dataDir}"

    mkdir -p "${cfg.dataDir}"

    exec ${pkgs.caddy}/bin/caddy run \
      --config "${caddyfile}" \
      --adapter caddyfile
  '';

  dnsmasqConf = pkgs.writeText "dnsmasq.conf" ''
    address=/internal/127.0.0.1
    listen-address=127.0.0.1
    port=${toString dnsPort}
    no-resolv
    no-poll
    no-hosts
    bind-interfaces
  '';

  dnsmasqScript = pkgs.writeShellScript "dnsmasq-launchd-service" ''
    set -euo pipefail
    exec ${pkgs.dnsmasq}/bin/dnsmasq \
      --no-daemon \
      --conf-file="${dnsmasqConf}"
  '';
in {
  options.myConfig.caddy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Caddy reverse proxy with .internal hostnames to local services";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Port for Caddy HTTP listener";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.local/share/caddy";
      description = "Directory for Caddy data (certs, config)";
    };

    hosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional hostname->upstream mappings (e.g. { \"app.internal\" = \"localhost:9000\"; })";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."resolver/localhost".text = ''
      nameserver 127.0.0.1
      port ${toString dnsPort}
    '';

    environment.etc."resolver/internal".text = ''
      nameserver 127.0.0.1
      port ${toString dnsPort}
    '';

    launchd.user.agents.dnsmasq = {
      command = dnsmasqScript;
      serviceConfig = {
        Label = "org.nixos.dnsmasq";
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${darwinHomeDir}/.local/share/caddy/dnsmasq.log";
        StandardErrorPath = "${darwinHomeDir}/.local/share/caddy/dnsmasq.error.log";
        WorkingDirectory = darwinHomeDir;
      };
    };

    launchd.user.agents.caddy = {
      command = caddyScript;
      serviceConfig = {
        Label = "org.nixos.caddy";
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${darwinHomeDir}/.local/share/caddy/caddy.log";
        StandardErrorPath = "${darwinHomeDir}/.local/share/caddy/caddy.error.log";
        WorkingDirectory = darwinHomeDir;
      };
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      mkdir -p "${darwinHomeDir}/.local/share/caddy"
    '';

    # Register caddy + dnsmasq in service registry
    myConfig.serviceRegistry = lib.mkMerge [
      (mkServiceRegistry "caddy" {
        displayName = "Caddy";
        port = cfg.port;
        label = "org.nixos.caddy";
        errorLog = "${darwinHomeDir}/.local/share/caddy/caddy.error.log";
        enabled = cfg.enable;
      })
      (mkServiceRegistry "dnsmasq" {
        displayName = "dnsmasq";
        port = dnsPort;
        label = "org.nixos.dnsmasq";
        errorLog = "${darwinHomeDir}/.local/share/caddy/dnsmasq.error.log";
        enabled = cfg.enable;
      })
    ];
  };
}
