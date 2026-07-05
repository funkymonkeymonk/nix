# Caddy reverse proxy + dnsmasq DNS resolver for Darwin (macOS)
# dnsmasq resolves *.internal → 127.0.0.1 (via /etc/resolver/internal)
# Caddy routes hostnames to local services on port 80.
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

  commonLib = import ../../common/lib.nix {};

  darwinHomeDir = commonLib.darwinHomeDir config;

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
  config = lib.mkIf cfg.enable {
    environment.etc."resolver/internal".text = ''
      nameserver 127.0.0.1
      port ${toString dnsPort}
    '';

    launchd.daemons.dnsmasq = {
      command = dnsmasqScript;
      serviceConfig = {
        Label = "com.dnsmasq.service";
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/dnsmasq.log";
        StandardErrorPath = "/tmp/dnsmasq.error.log";
        WorkingDirectory = darwinHomeDir;
      };
    };

    launchd.daemons.caddy = {
      command = caddyScript;
      serviceConfig = {
        Label = "com.caddy.service";
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/caddy.log";
        StandardErrorPath = "/tmp/caddy.error.log";
        WorkingDirectory = darwinHomeDir;
      };
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      mkdir -p "${cfg.dataDir}"
    '';

    # Register caddy + dnsmasq in service registry
    myConfig.serviceRegistry = lib.mkMerge [
      (lib.optionalAttrs cfg.enable {
        caddy = {
          name = "Caddy";
          port = cfg.port;
          launchdLabel = "com.caddy.service";
          errorLog = "/tmp/caddy.error.log";
        };
        dnsmasq = {
          name = "dnsmasq";
          port = 5353;
          launchdLabel = "com.dnsmasq.service";
          errorLog = "/tmp/dnsmasq.error.log";
        };
      })
    ];
  };
}
