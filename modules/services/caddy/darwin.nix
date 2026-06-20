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

      echo "Verifying LLM stack services..." >&2
      ${builtins.concatStringsSep "\n" (map (svc: ''
        if launchctl list "${svc.launchdLabel}" >/dev/null 2>&1; then
          state=$(launchctl list "${svc.launchdLabel}" 2>&1 | grep -c '"PID"')
          if [ "$state" -eq 0 ]; then
            if [ -f "${svc.errorLog}" ] && grep -q "address already in use" "${svc.errorLog}" 2>/dev/null; then
              echo "  ${svc.name}: PORT CONFLICT detected — aborting" >&2
              exit 1
            fi
            waited=0
            while [ "$state" -eq 0 ] && [ "$waited" -lt 30 ]; do
              sleep 1; state=$(launchctl list "${svc.launchdLabel}" 2>&1 | grep -c '"PID"')
              waited=$((waited + 1))
            done
          fi
          if [ "$state" -gt 0 ]; then
            echo "  ${svc.name}: running" >&2
          else
            echo "  ${svc.name}: NOT RUNNING after 30s — aborting" >&2; exit 1
          fi
        else
          echo "  ${svc.name}: not registered" >&2; exit 1
        fi
      '') (builtins.attrValues config.myConfig.serviceRegistry))}
      echo "All LLM stack services running" >&2

      # Write stack report
      REPORT="${cfg.dataDir}/stack-report.json"
      TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      printf '%s\n' '${builtins.toJSON {
        timestamp = "@RUNTIME@";
        result = "pass";
        services = builtins.listToAttrs (map (svc: {
          name = svc.launchdLabel;
          value = {name = svc.name; port = svc.port; status = "running";};
        }) (builtins.attrValues config.myConfig.serviceRegistry));
      }}' | sed "s/@RUNTIME@/$TS/" > "$REPORT"
      echo "Stack report: $REPORT" >&2
    '';

    # Register caddy + dnsmasq in service registry
    myConfig.serviceRegistry = mkMerge [
      (optionalAttrs cfg.enable {
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
