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
  ultraRemoteDiskConfig = lib.attrByPath ["myConfig" "ultraMediaDownloadStage" "remoteDisk"] {} config;
  ultraRemoteDiskCapacityBytes = ultraRemoteDiskConfig.capacityBytes or 4000000000000;
  ultraRemoteDiskWarningThresholdBytes = ultraRemoteDiskConfig.warningThresholdBytes or 3000000000000;

  ultraStageFailureQuery = ''sum(count_over_time({host="drlight",service="systemd",severity="err"} | json | UNIT="ultra-media-download-stage.service" | JOB_RESULT="failed" [5m]))'';

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

  ultraStageDashboard = pkgs.writeText "ultra-media-download-stage.json" (builtins.toJSON {
    title = "drlight: Ultra Download Staging";
    uid = "drlight-ultra-media-sync";
    schemaVersion = 39;
    refresh = "1m";
    time = {
      from = "now-24h";
      to = "now";
    };
    panels = [
      {
        id = 3;
        title = "Failed runs (24h)";
        type = "stat";
        gridPos = {
          h = 6;
          w = 6;
          x = 0;
          y = 0;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''sum(count_over_time({host="drlight",service="systemd",severity="err"} | json | UNIT="ultra-media-download-stage.service" | JOB_RESULT="failed" [24h]))'';
            queryType = "instant";
            refId = "A";
          }
        ];
      }
      {
        id = 4;
        title = "Sync worker log activity (5m)";
        type = "timeseries";
        gridPos = {
          h = 6;
          w = 6;
          x = 6;
          y = 0;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''sum(count_over_time({host="drlight",service="ultra-media-download-stage-start"}[5m]))'';
            refId = "A";
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
          y = 0;
        };
        fieldConfig.defaults.unit = "bytes";
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''node_filesystem_avail_bytes{job="node",instance="drlight:9100",mountpoint="/srv/media"}'';
            refId = "A";
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
          y = 6;
        };
        fieldConfig.defaults.unit = "percent";
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''100 * (1 - node_filesystem_avail_bytes{job="node",instance="drlight:9100",mountpoint="/srv/media"} / node_filesystem_size_bytes{job="node",instance="drlight:9100",mountpoint="/srv/media"})'';
            refId = "A";
          }
        ];
      }
      {
        id = 10;
        title = "Sync time behind history";
        type = "timeseries";
        gridPos = {
          h = 6;
          w = 12;
          x = 12;
          y = 6;
        };
        fieldConfig.defaults.unit = "s";
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''max(last_over_time({host="drlight",service="ultra-media-download-stage-start"} | json | line_format "{{.message}}" | json | event="staging_progress" | unwrap time_behind_seconds | __error__="" [24h]))'';
            refId = "A";
          }
        ];
      }
      {
        id = 11;
        title = "Remote seedbox disk usage";
        type = "timeseries";
        gridPos = {
          h = 7;
          w = 12;
          x = 0;
          y = 12;
        };
        fieldConfig.defaults = {
          unit = "decbytes";
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "orange";
                value = ultraRemoteDiskWarningThresholdBytes;
              }
              {
                color = "red";
                value = ultraRemoteDiskCapacityBytes;
              }
            ];
          };
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_seedbox_storage_used_bytes{job="node",instance="drlight:9100"}'';
            refId = "A";
          }
        ];
      }
      {
        id = 13;
        title = "Current sync state";
        type = "stat";
        gridPos = {
          h = 6;
          w = 6;
          x = 0;
          y = 19;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_active{job="node",instance="drlight:9100"}'';
            legendFormat = "active";
            refId = "A";
          }
        ];
      }
      {
        id = 14;
        title = "Sync queue progress";
        type = "timeseries";
        gridPos = {
          h = 6;
          w = 6;
          x = 18;
          y = 12;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrents_published{job="node",instance="drlight:9100"}'';
            legendFormat = "staged";
            refId = "A";
          }
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrents_total{job="node",instance="drlight:9100"}'';
            legendFormat = "total";
            refId = "B";
          }
        ];
      }
      {
        id = 15;
        title = "Sync rate and overall ETA";
        type = "timeseries";
        gridPos = {
          h = 6;
          w = 6;
          x = 12;
          y = 12;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_bytes_per_second{job="node",instance="drlight:9100"}'';
            legendFormat = "bytes/sec";
            refId = "A";
          }
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_eta_seconds{job="node",instance="drlight:9100"} >= 0'';
            legendFormat = "ETA seconds";
            refId = "B";
          }
        ];
      }
      {
        id = 16;
        title = "Current media sync queue";
        type = "table";
        gridPos = {
          h = 10;
          w = 24;
          x = 0;
          y = 25;
        };
        fieldConfig.defaults = {
          custom = {
            inspect = false;
          };
          mappings = [
            {
              type = "value";
              options = {
                "-1" = {text = "Unknown";};
                "0" = {text = "No";};
                "1" = {text = "Yes";};
              };
            }
          ];
        };
        transformations = [
          {
            id = "joinByField";
            options = {
              byField = "torrent_id";
              mode = "outer";
            };
          }
          {
            id = "organize";
            options = {
              excludeByName = {
                Time = true;
                Value = true;
              };
              indexByName = {
                title = 0;
                category = 1;
                torrent_id = 2;
                ultra_media_sync_torrent_eta_seconds = 3;
                ultra_media_sync_torrent_imported = 4;
                ultra_media_sync_torrent_jellyfin = 5;
              };
              renameByName = {
                ultra_media_sync_torrent_eta_seconds = "ETA seconds";
                ultra_media_sync_torrent_imported = "Imported";
                ultra_media_sync_torrent_jellyfin = "In Jellyfin";
              };
            };
          }
        ];
        options = {
          sortBy = [
            {
              desc = false;
              displayName = "ETA seconds";
            }
          ];
          cellHeight = "sm";
          footer = {show = false;};
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrent_eta_seconds{job="node",instance="drlight:9100"}'';
            format = "table";
            instant = true;
            refId = "A";
          }
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrent_imported{job="node",instance="drlight:9100"}'';
            format = "table";
            instant = true;
            refId = "B";
          }
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrent_jellyfin{job="node",instance="drlight:9100"}'';
            format = "table";
            instant = true;
            refId = "C";
          }
        ];
      }
      {
        id = 17;
        title = "Quota guard live usage";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 35;
        };
        fieldConfig.defaults = {
          unit = "decbytes";
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "orange";
                value = 3500000000000;
              }
              {
                color = "red";
                value = 3800000000000;
              }
            ];
          };
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_seedbox_download_guard_used_bytes{job="node",instance="drlight:9100"}'';
            refId = "A";
          }
        ];
      }
      {
        id = 18;
        title = "Quota guard state";
        type = "stat";
        gridPos = {
          h = 8;
          w = 6;
          x = 12;
          y = 35;
        };
        fieldConfig.defaults = {
          mappings = [
            {
              type = "value";
              options = {
                "0" = {
                  text = "Downloads allowed";
                  color = "green";
                };
                "1" = {
                  text = "Seeding only";
                  color = "orange";
                };
              };
            }
          ];
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "orange";
                value = 1;
              }
            ];
          };
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_seedbox_download_guard_active{job="node",instance="drlight:9100"}'';
            refId = "A";
          }
        ];
      }
      {
        id = 19;
        title = "Guard-paused torrents";
        type = "stat";
        gridPos = {
          h = 8;
          w = 6;
          x = 18;
          y = 35;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_seedbox_download_guard_paused_torrents{job="node",instance="drlight:9100"}'';
            refId = "A";
          }
        ];
      }
      {
        id = 20;
        title = "Quota guard activity (7d)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 24;
          x = 0;
          y = 43;
        };
        fieldConfig.defaults.unit = "short";
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''sum(increase(ultra_seedbox_download_guard_pauses_total{job="node",instance="drlight:9100"}[7d]))'';
            legendFormat = "pause events";
            refId = "A";
          }
          {
            datasource.type = "prometheus";
            expr = ''sum(increase(ultra_seedbox_download_guard_resumes_total{job="node",instance="drlight:9100"}[7d]))'';
            legendFormat = "resume events";
            refId = "B";
          }
          {
            datasource.type = "prometheus";
            expr = ''sum(increase(ultra_seedbox_download_guard_probe_failures_total{job="node",instance="drlight:9100"}[7d]))'';
            legendFormat = "quota probe failures";
            refId = "C";
          }
          {
            datasource.type = "prometheus";
            expr = ''sum(increase(ultra_seedbox_download_guard_rpc_failures_total{job="node",instance="drlight:9100"}[7d]))'';
            legendFormat = "RPC failures";
            refId = "D";
          }
        ];
      }
    ];
  });

  ultraStageFailureAlerting = {
    apiVersion = 1;
    groups = [
      {
        orgId = 1;
        name = "ultra-download-staging";
        folder = "Media";
        interval = "1m";
        rules = [
          {
            uid = "ultra-media-sync-failure";
            title = "Ultra sync and cleanup failed";
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
                  expr = ultraStageFailureQuery;
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
              summary = "Ultra sync and cleanup failed on drlight";
              description = "systemd reported JOB_RESULT=failed for ultra-media-download-stage.service. See the Ultra Download Staging dashboard for the JSON run summary.";
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
    cp ${ultraStageDashboard} $out/ultra-media-download-stage.json
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
        alerting.rules.settings = ultraStageFailureAlerting;
      };
    };

    # systemd runs ExecStartPre as Grafana, whose home is the writable data
    # directory. This creates the file with Grafana ownership and restrictive
    # mode without placing key material in a Nix derivation.
    systemd.services.grafana.preStart = lib.mkBefore generateSecretKey;
  };
}
