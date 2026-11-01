# Native NixOS Grafana service for the type-observability archetype.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.grafana;

  dashboard = pkgs.writeText "system-overview.json" (builtins.toJSON {
    title = "protoman: System Overview";
    uid = "protoman-system-overview";
    schemaVersion = 39;
    panels = [
      {
        id = 1;
        title = "CPU Usage";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 0;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''100 - (avg(rate(node_cpu_seconds_total{job="node",mode="idle"}[5m])) * 100)'';
          }
        ];
      }
      {
        id = 2;
        title = "Memory Available";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 0;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"} * 100'';
          }
        ];
      }
      {
        id = 3;
        title = "Disk Free";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 8;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''node_filesystem_avail_bytes{job="node",fstype!="tmpfs"} / node_filesystem_size_bytes{job="node",fstype!="tmpfs"} * 100'';
          }
        ];
      }
      {
        id = 4;
        title = "Service Logs";
        type = "logs";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 8;
        };
        targets = [
          {
            datasource.type = "loki";
            expr = ''{host=~".+"}'';
          }
        ];
      }
    ];
  });

  dashboardsDir = pkgs.runCommand "grafana-dashboards" {} ''
    mkdir -p $out
    cp ${dashboard} $out/system-overview.json
  '';

  grafanaSecretKey = "/var/lib/grafana/secret_key";
  generateSecretKey = ''
    set -eu
    if [ ! -e ${grafanaSecretKey} ]; then
      umask 077
      key_tmp="$(${pkgs.coreutils}/bin/mktemp /var/lib/grafana/.secret_key.XXXXXX)"
      ${pkgs.openssl}/bin/openssl rand -hex 32 > "$key_tmp"
      ${pkgs.coreutils}/bin/chmod 0600 "$key_tmp"
      ${pkgs.coreutils}/bin/mv "$key_tmp" ${grafanaSecretKey}
    fi
  '';
in {
  options.myConfig.grafana.enable = lib.mkEnableOption "Grafana dashboard and visualization server";

  config = lib.mkIf cfg.enable {
    myConfig.onepassword.secrets = {
      grafanaUsername = {
        reference = "Grafana - Home/username";
        path = "/run/secrets/grafana-username";
        mode = "0400";
        owner = "grafana";
        group = "grafana";
        services = ["grafana"];
      };
      grafanaPassword = {
        reference = "Grafana - Home/password";
        path = "/run/secrets/grafana-password";
        mode = "0400";
        owner = "grafana";
        group = "grafana";
        services = ["grafana"];
      };
    };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 3000;
          domain = "grafana.home.buildingbananas.com";
        };
        security = {
          admin_user = "$__file{/run/secrets/grafana-username}";
          admin_password = "$__file{/run/secrets/grafana-password}";
          secret_key = "$__file{${grafanaSecretKey}}";
        };
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:${toString config.myConfig.prometheus.port}";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            access = "proxy";
            url = "http://127.0.0.1:${toString config.myConfig.loki.port}";
          }
        ];
        dashboards.settings.providers = [
          {
            name = "protoman";
            type = "file";
            disableDeletion = true;
            editable = false;
            options.path = dashboardsDir;
          }
        ];
      };
    };

    # systemd runs ExecStartPre as Grafana, whose home is the writable data
    # directory. This creates the file with Grafana ownership and restrictive
    # mode without placing key material in a Nix derivation.
    systemd.services.grafana.preStart = lib.mkBefore generateSecretKey;
  };
}
