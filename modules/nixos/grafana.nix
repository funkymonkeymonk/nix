# Native NixOS Grafana service for the type-observability archetype.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.grafana;
  # Match drlight's existing provisioned Loki datasource instead of changing
  # its UID, which would break Grafana's persistent datasource references.
  lokiDatasourceUid = "P8E80F9AEF21F6940";

  ultraSyncFailureQuery = ''sum(count_over_time({host="drlight",service="systemd",severity="err"} | json | UNIT="ultra-media-sync.service" | JOB_RESULT="failed" [5m]))'';

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

  ultraSyncDashboard = pkgs.writeText "ultra-media-sync.json" (builtins.toJSON {
    title = "drlight: Ultra Media Sync";
    uid = "drlight-ultra-media-sync";
    schemaVersion = 39;
    refresh = "1m";
    time = {
      from = "now-24h";
      to = "now";
    };
    panels = [
      {
        id = 1;
        title = "Recent rsync logs";
        type = "logs";
        gridPos = {
          h = 10;
          w = 12;
          x = 0;
          y = 0;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''{host="drlight",service="ultra-media-sync-start"}'';
          }
        ];
      }
      {
        id = 2;
        title = "Systemd run status";
        type = "logs";
        gridPos = {
          h = 10;
          w = 12;
          x = 12;
          y = 0;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''{host="drlight",service="systemd"} | json | UNIT="ultra-media-sync.service"'';
          }
        ];
      }
      {
        id = 3;
        title = "Failed runs (24h)";
        type = "stat";
        gridPos = {
          h = 6;
          w = 6;
          x = 0;
          y = 10;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''sum(count_over_time({host="drlight",service="systemd",severity="err"} | json | UNIT="ultra-media-sync.service" | JOB_RESULT="failed" [24h]))'';
            queryType = "instant";
          }
        ];
      }
      {
        id = 4;
        title = "Rsync log activity (5m)";
        type = "timeseries";
        gridPos = {
          h = 6;
          w = 6;
          x = 6;
          y = 10;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''sum(count_over_time({host="drlight",service="ultra-media-sync-start"}[5m]))'';
          }
        ];
      }
      {
        id = 5;
        title = "Media library free space";
        type = "timeseries";
        gridPos = {
          h = 6;
          w = 12;
          x = 12;
          y = 10;
        };
        fieldConfig.defaults.unit = "bytes";
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''node_filesystem_avail_bytes{job="node",instance="drlight:9100",mountpoint="/srv/media"}'';
          }
        ];
      }
      {
        id = 6;
        title = "Media library used";
        type = "timeseries";
        gridPos = {
          h = 6;
          w = 12;
          x = 0;
          y = 16;
        };
        fieldConfig.defaults.unit = "percent";
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''100 * (1 - node_filesystem_avail_bytes{job="node",instance="drlight:9100",mountpoint="/srv/media"} / node_filesystem_size_bytes{job="node",instance="drlight:9100",mountpoint="/srv/media"})'';
          }
        ];
      }
    ];
  });

  ultraSyncFailureAlerting = {
    apiVersion = 1;
    groups = [
      {
        orgId = 1;
        name = "ultra-media-sync";
        folder = "Media";
        interval = "1m";
        rules = [
          {
            uid = "ultra-media-sync-failure";
            title = "Ultra media sync failed";
            condition = "A";
            data = [
              {
                refId = "A";
                queryType = "instant";
                relativeTimeRange = {
                  from = 300;
                  to = 0;
                };
                datasourceUid = lokiDatasourceUid;
                model = {
                  datasource = {
                    type = "loki";
                    uid = lokiDatasourceUid;
                  };
                  editorMode = "code";
                  expr = ultraSyncFailureQuery;
                  queryType = "instant";
                  refId = "A";
                  intervalMs = 1000;
                  maxDataPoints = 43200;
                };
              }
            ];
            noDataState = "OK";
            execErrState = "Error";
            for = "0s";
            annotations = {
              summary = "Ultra media sync failed on drlight";
              description = "systemd reported JOB_RESULT=failed for ultra-media-sync.service. See the Ultra Media Sync dashboard for logs.";
            };
            labels = {
              severity = "critical";
              host = "drlight";
            };
            isPaused = false;
          }
        ];
      }
    ];
  };

  dashboardsDir = pkgs.runCommand "grafana-dashboards" {} ''
    mkdir -p $out
    cp ${dashboard} $out/system-overview.json
    cp ${ultraSyncDashboard} $out/ultra-media-sync.json
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
            uid = lokiDatasourceUid;
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
        alerting.rules.settings = ultraSyncFailureAlerting;
      };
    };

    # systemd runs ExecStartPre as Grafana, whose home is the writable data
    # directory. This creates the file with Grafana ownership and restrictive
    # mode without placing key material in a Nix derivation.
    systemd.services.grafana.preStart = lib.mkBefore generateSecretKey;
  };
}
