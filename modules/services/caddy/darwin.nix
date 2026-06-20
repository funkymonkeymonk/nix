# Caddy reverse proxy + dnsmasq DNS resolver for Darwin (macOS)
# dnsmasq resolves *.internal → 127.0.0.1 (via /etc/resolver/internal)
# Caddy routes hostnames to local services on port 80.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.caddy;
  searxngCfg = config.myConfig.searxng;
  bifrostCfg = config.myConfig.bifrost;
  vaneCfg = config.myConfig.vane;
  vmlxCfg = config.myConfig.vmlx;

  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "monkey";
  darwinHomeDir = "/Users/${primaryUser}";

  dnsPort = 5353;

  serviceRoutes =
    []
    ++ optional (searxngCfg.enable && searxngCfg.port != cfg.port) {
      host = "searxng.internal";
      upstream = "localhost:${toString searxngCfg.port}";
    }
    ++ optional (bifrostCfg.enable && bifrostCfg.port != cfg.port) {
      host = "bifrost.internal";
      upstream = "localhost:${toString bifrostCfg.port}";
    }
    ++ optional (vaneCfg.enable && vaneCfg.port != cfg.port) {
      host = "vane.internal";
      upstream = "localhost:${toString vaneCfg.port}";
    }
    ++ optional (vmlxCfg.enable && vmlxCfg.server.port != cfg.port) {
      host = "vmlx.internal";
      upstream = "localhost:${toString vmlxCfg.server.port}";
    };

  allRoutes = serviceRoutes ++ (mapAttrsToList (host: upstream: {inherit host upstream;}) cfg.hosts);

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

    ${concatMapStrings routeBlock allRoutes}
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
  config = mkIf cfg.enable {
    environment.etc."resolver/internal".text = ''
      nameserver 127.0.0.1
      port ${toString dnsPort}
    '';

    launchd.daemons.dnsmasq = {
      serviceConfig = {
        Label = "com.dnsmasq.service";
        ProgramArguments = ["${dnsmasqScript}"];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/dnsmasq.log";
        StandardErrorPath = "/tmp/dnsmasq.error.log";
        WorkingDirectory = darwinHomeDir;
      };
    };

    launchd.daemons.caddy = {
      serviceConfig = {
        Label = "com.caddy.service";
        ProgramArguments = ["${caddyScript}"];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/caddy.log";
        StandardErrorPath = "/tmp/caddy.error.log";
        WorkingDirectory = darwinHomeDir;
      };
    };

    system.activationScripts.postActivation.text = mkAfter ''
      mkdir -p "${cfg.dataDir}"

      # Verify launchd services come up, fail if any don't
      echo "Verifying LLM stack services..." >&2
      for svc in org.vmlx.server com.bifrost.service com.caddy.service com.dnsmasq.service com.vane.service; do
        if launchctl list "$svc" >/dev/null 2>&1; then
          state=$(launchctl list "$svc" 2>&1 | grep -c '"PID"')
          waited=0
          while [ "$state" -eq 0 ] && [ "$waited" -lt 30 ]; do
            sleep 1
            state=$(launchctl list "$svc" 2>&1 | grep -c '"PID"')
            waited=$((waited + 1))
          done
          if [ "$state" -gt 0 ]; then
            echo "  $svc: running" >&2
          else
            echo "  $svc: NOT RUNNING after 30s — aborting" >&2
            exit 1
          fi
        else
          echo "  $svc: not registered" >&2
          exit 1
        fi
      done
      echo "All LLM stack services running" >&2
    '';
  };
}
