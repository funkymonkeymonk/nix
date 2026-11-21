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
        id = 1;
        title = "Recent sync and cleanup JSON logs";
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
            expr = ''{host="drlight",service="ultra-media-download-stage-start"}'';
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
            expr = ''{host="drlight",service="systemd"} | json | UNIT="ultra-media-download-stage.service"'';
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
            expr = ''sum(count_over_time({host="drlight",service="systemd",severity="err"} | json | UNIT="ultra-media-download-stage.service" | JOB_RESULT="failed" [24h]))'';
            queryType = "instant";
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
          y = 10;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''sum(count_over_time({host="drlight",service="ultra-media-download-stage-start"}[5m]))'';
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
      {
        id = 7;
        title = "Transfer progress and ETA";
        type = "logs";
        gridPos = {
          h = 10;
          w = 24;
          x = 0;
          y = 22;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''{host="drlight",service="ultra-media-download-stage-start"} | json | line_format "{{.message}}" | json | event="staging_progress" | line_format "torrents={{.torrents_published}}/{{.torrents_total}} files={{.files_transferred}}+{{.files_reused}} reused/{{.files_total}} bytes={{.bytes_transferred}}+{{.bytes_reused}} reused/{{.bytes_total}} percent={{.percent_complete}} rate={{.bytes_per_second}} eta={{.eta_seconds}} lag={{.time_behind_seconds}} unorderable={{.unorderable_completed_torrents}} receipts={{.receipts_created}}"'';
          }
        ];
      }
      {
        id = 8;
        title = "Cleanup queue and removal results";
        type = "logs";
        gridPos = {
          h = 8;
          w = 24;
          x = 0;
          y = 32;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''{host="drlight",service="ultra-media-download-stage-start"} | json | line_format "{{.message}}" | json | event="cleanup_queue_summary" | line_format "queued={{.queued}} pending={{.pending_after_run}} removed={{.removed}} blocked={{.blocked}} stale={{.stale_or_missing}} reasons={{.reasons}}"'';
          }
        ];
      }
      {
        id = 9;
        title = "Oldest unstaged completion age";
        type = "stat";
        gridPos = {
          h = 6;
          w = 6;
          x = 0;
          y = 40;
        };
        fieldConfig.defaults.unit = "s";
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''last_over_time({host="drlight",service="ultra-media-download-stage-start"} | json | line_format "{{.message}}" | json | unwrap time_behind_seconds | __error__="" [24h])'';
          }
        ];
      }
      {
        id = 10;
        title = "Sync time behind history";
        type = "timeseries";
        gridPos = {
          h = 6;
          w = 18;
          x = 6;
          y = 40;
        };
        fieldConfig.defaults.unit = "s";
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''last_over_time({host="drlight",service="ultra-media-download-stage-start"} | json | line_format "{{.message}}" | json | unwrap time_behind_seconds | __error__="" [24h])'';
          }
        ];
      }
      {
        id = 11;
        title = "Remote seedbox disk usage";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 24;
          x = 0;
          y = 46;
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
          }
        ];
      }
      {
        id = 12;
        title = "Combined sync and cleanup run summary";
        type = "logs";
        gridPos = {
          h = 8;
          w = 24;
          x = 0;
          y = 54;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            expr = ''{host="drlight",service="ultra-media-download-stage-start"} | json | line_format "{{.message}}" | json | event="sync_run_summary" | line_format "stage={{.staging_status}} torrents={{.torrents_staged}}/{{.torrents_total}} failed={{.torrents_failed}} files={{.files_transferred}}+{{.files_reused}} reused bytes={{.bytes_transferred}}+{{.bytes_reused}} reused cleanup={{.cleanup_status}} result={{.run_status}} removed={{.cleanup_removed}} blocked={{.cleanup_blocked}} pending={{.pending_after_run}} reasons={{.cleanup_reasons}}"'';
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
          y = 62;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_active{job="node",instance="drlight:9100"}'';
            legendFormat = "active";
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
          x = 6;
          y = 62;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrents_published{job="node",instance="drlight:9100"}'';
            legendFormat = "published";
          }
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrents_total{job="node",instance="drlight:9100"}'';
            legendFormat = "total";
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
          y = 62;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_bytes_per_second{job="node",instance="drlight:9100"}'';
            legendFormat = "bytes/sec";
          }
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_eta_seconds{job="node",instance="drlight:9100"} >= 0'';
            legendFormat = "ETA seconds";
          }
        ];
      }
      {
        id = 16;
        title = "Torrent queue: size, remaining, ETA";
        type = "table";
        gridPos = {
          h = 12;
          w = 24;
          x = 0;
          y = 68;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrent_total_bytes{job="node",instance="drlight:9100"}'';
            legendFormat = "size";
          }
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrent_remaining_bytes{job="node",instance="drlight:9100"}'';
            legendFormat = "remaining";
          }
          {
            datasource.type = "prometheus";
            expr = ''ultra_media_sync_torrent_eta_seconds{job="node",instance="drlight:9100"} >= 0'';
            legendFormat = "ETA";
          }
        ];
        transformations = [
          {
            id = "labelsToFields";
            options = {mode = "columns";};
          }
          {
            id = "joinByField";
            options = {
              byField = "torrent_id";
              mode = "outer";
            };
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
