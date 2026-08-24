# Prometheus + node_exporter observability tests
# Validates option defaults, custom values, and generated launchd scripts.
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  # Stub options that the prometheus scrape config reads from other modules.
  dependencyOptions = {
    options.myConfig.bifrost = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8081;
      };
    };
    options.myConfig.nodeExporter = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 9100;
      };
    };
    options.myConfig.vllmMlx = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      server.port = lib.mkOption {
        type = lib.types.port;
        default = 8300;
      };
    };
    options.myConfig.alertmanager = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 9093;
      };
      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
      };
    };
  };

  nodeExporterDefaults =
    (lib.evalModules {
      modules = stubs.base ++ stubs.darwinService ++ [../modules/services/node-exporter/darwin.nix];
    }).config.myConfig.nodeExporter;

  nodeExporterCustom =
    (lib.evalModules {
      modules =
        stubs.base
        ++ stubs.darwinService
        ++ [
          ../modules/services/node-exporter/darwin.nix
          {
            config.myConfig.users = [{name = "monkey";}];
            config.myConfig.nodeExporter = {
              enable = true;
              port = 9101;
            };
          }
        ];
    }).config.myConfig.nodeExporter;

  prometheusDefaults =
    (lib.evalModules {
      modules = stubs.base ++ stubs.darwinService ++ [../modules/services/prometheus/darwin.nix];
    }).config.myConfig.prometheus;

  prometheusCustom =
    (lib.evalModules {
      modules =
        stubs.base
        ++ stubs.darwinService
        ++ [
          ../modules/services/prometheus/darwin.nix
          dependencyOptions
          {
            config.myConfig.users = [{name = "monkey";}];
            config.myConfig.prometheus = {
              enable = true;
              port = 9091;
              retention = "24h";
              bindAddress = "192.168.83.20";
            };
            config.myConfig.nodeExporter.port = 9101;
          }
        ];
    }).config;

  prometheusEnabledScript = prometheusCustom.launchd.daemons.prometheus.command;
in {
  nodeExporterOptionsTest = pkgs.runCommand "test-node-exporter-options" {} ''
    echo "=== Testing node_exporter Option Defaults ==="

    ${
      if !nodeExporterDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if nodeExporterDefaults.port == 9100
      then ''echo "  port default = 9100: OK"''
      else ''echo "  port should default to 9100!"; exit 1''
    }

    echo "All node_exporter option defaults verified"
    touch $out
  '';

  nodeExporterCustomOptionsTest = pkgs.runCommand "test-node-exporter-custom-options" {} ''
    echo "=== Testing node_exporter Custom Options ==="

    ${
      if nodeExporterCustom.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if nodeExporterCustom.port == 9101
      then ''echo "  port = 9101: OK"''
      else ''echo "  port should be 9101!"; exit 1''
    }

    echo "All node_exporter custom options verified"
    touch $out
  '';

  prometheusOptionsTest = pkgs.runCommand "test-prometheus-options" {} ''
    echo "=== Testing Prometheus Option Defaults ==="

    ${
      if !prometheusDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if prometheusDefaults.port == 9090
      then ''echo "  port default = 9090: OK"''
      else ''echo "  port should default to 9090!"; exit 1''
    }

    ${
      if prometheusDefaults.retention == "7d"
      then ''echo "  retention default = 7d: OK"''
      else ''echo "  retention should default to 7d!"; exit 1''
    }

    ${
      if prometheusDefaults.bindAddress == "127.0.0.1"
      then ''echo "  bindAddress default = 127.0.0.1 (loopback-only, safe default): OK"''
      else ''echo "  bindAddress should default to 127.0.0.1!"; exit 1''
    }

    echo "All Prometheus option defaults verified"
    touch $out
  '';

  prometheusCustomOptionsTest = pkgs.runCommand "test-prometheus-custom-options" {} ''
    echo "=== Testing Prometheus Custom Options ==="

    ${
      if prometheusCustom.myConfig.prometheus.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if prometheusCustom.myConfig.prometheus.port == 9091
      then ''echo "  port = 9091: OK"''
      else ''echo "  port should be 9091!"; exit 1''
    }

    ${
      if prometheusCustom.myConfig.prometheus.retention == "24h"
      then ''echo "  retention = 24h: OK"''
      else ''echo "  retention should be 24h!"; exit 1''
    }

    ${
      if prometheusCustom.myConfig.prometheus.bindAddress == "192.168.83.20"
      then ''echo "  bindAddress = 192.168.83.20: OK"''
      else ''echo "  bindAddress should be 192.168.83.20!"; exit 1''
    }

    echo "All Prometheus custom options verified"
    touch $out
  '';

  # Verify the generated launchd script listens on the configured port and uses
  # the configured retention. This catches the stale-listenAddress bug where
  # changing `port` left Prometheus bound to the old port.
  prometheusGeneratedScriptTest = pkgs.runCommand "test-prometheus-generated-script" {} ''
    echo "=== Testing Prometheus Generated Script ==="

    SCRIPT=${prometheusEnabledScript}

    if grep -q -- '--web.listen-address=192.168.83.20:9091' "$SCRIPT"; then
      echo "  listen address derived from bindAddress+port (192.168.83.20:9091): OK"
    else
      echo "  FAIL: script should listen on 192.168.83.20:9091"; exit 1
    fi

    if grep -q -- '--storage.tsdb.retention.time 24h' "$SCRIPT"; then
      echo "  retention time = 24h: OK"
    else
      echo "  FAIL: script should set retention to 24h"; exit 1
    fi

    echo "All Prometheus generated script tests passed"
    touch $out
  '';

  # Verify the generated prometheus.yml scrape config uses the configured ports
  # for node-exporter, bifrost, and vllm-mlx.
  prometheusScrapeConfigTest = pkgs.runCommand "test-prometheus-scrape-config" {} ''
    echo "=== Testing Prometheus Scrape Config ==="

    SCRIPT=${prometheusEnabledScript}
    CONFIG=$(grep -o -- '--config.file /nix/store/[^ ]*' "$SCRIPT" | head -1 | cut -d' ' -f2)

    if grep -q '"targets":\["localhost:9101"\]' "$CONFIG"; then
      echo "  node job targets localhost:9101: OK"
    else
      echo "  FAIL: node job should target localhost:9101"; exit 1
    fi

    if grep -q '"targets":\["localhost:8081"\]' "$CONFIG"; then
      echo "  bifrost job targets localhost:8081: OK"
    else
      echo "  FAIL: bifrost job should target localhost:8081"; exit 1
    fi

    if grep -q '"targets":\["localhost:8300"\]' "$CONFIG"; then
      echo "  vllm-mlx job targets localhost:8300: OK"
    else
      echo "  FAIL: vllm-mlx job should target localhost:8300"; exit 1
    fi

    echo "All Prometheus scrape config tests passed"
    touch $out
  '';

  # Verify Prometheus wires up basic alert rules and points to Alertmanager
  # using the configured Alertmanager bindAddress/port (not hardcoded).
  prometheusAlertingConfigTest = pkgs.runCommand "test-prometheus-alerting-config" {} ''
    echo "=== Testing Prometheus Alerting Config ==="

    SCRIPT=${prometheusEnabledScript}
    CONFIG=$(grep -o -- '--config.file /nix/store/[^ ]*' "$SCRIPT" | head -1 | cut -d' ' -f2)

    if grep -q '"targets":\["127.0.0.1:9093"\]' "$CONFIG"; then
      echo "  alertmanagers static config targets 127.0.0.1:9093: OK"
    else
      echo "  FAIL: alertmanagers static config should target 127.0.0.1:9093"; exit 1
    fi

    RULE_FILE=$(grep -o '"rule_files":\["[^"]*"\]' "$CONFIG" | grep -o '/nix/store/[^"]*')
    if [ -n "$RULE_FILE" ] && [ -f "$RULE_FILE" ]; then
      echo "  rule_files references an existing file: OK"
    else
      echo "  FAIL: rule_files should reference an existing alert rules file"; exit 1
    fi

    if grep -q '"alert":"PrometheusTargetDown"' "$RULE_FILE"; then
      echo "  basic PrometheusTargetDown alert rule present: OK"
    else
      echo "  FAIL: rule file should define a PrometheusTargetDown alert"; exit 1
    fi

    echo "All Prometheus alerting config tests passed"
    touch $out
  '';
}
