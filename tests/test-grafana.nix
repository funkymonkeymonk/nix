# Grafana option tests
# Validates option defaults, custom values, and generated provisioning
# (datasources + dashboard) for modules/services/grafana/darwin.nix.
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  grafanaDefaults =
    (lib.evalModules {
      modules = stubs.grafana;
    }).config.myConfig.grafana;

  grafanaCustom =
    (lib.evalModules {
      modules =
        stubs.grafana
        ++ [
          {
            config.myConfig.users = [{name = "monkey";}];
            config.myConfig.prometheus.port = 9091;
            config.myConfig.loki.port = 3101;
            config.myConfig.grafana = {
              enable = true;
              port = 3001;
            };
          }
        ];
    }).config;

  grafanaEnabledScript = grafanaCustom.launchd.daemons.grafana.command;
in {
  grafanaOptionsTest = pkgs.runCommand "test-grafana-options" {} ''
    echo "=== Testing Grafana Option Defaults ==="

    ${
      if !grafanaDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if grafanaDefaults.port == 3000
      then ''echo "  port default = 3000: OK"''
      else ''echo "  port should default to 3000!"; exit 1''
    }

    echo "All Grafana option defaults verified"
    touch $out
  '';

  grafanaCustomOptionsTest = pkgs.runCommand "test-grafana-custom-options" {} ''
    echo "=== Testing Grafana Custom Options ==="

    ${
      if grafanaCustom.myConfig.grafana.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if grafanaCustom.myConfig.grafana.port == 3001
      then ''echo "  port = 3001: OK"''
      else ''echo "  port should be 3001!"; exit 1''
    }

    echo "All Grafana custom options verified"
    touch $out
  '';

  # Verify Prometheus and Loki are wired as datasources, using the
  # configured ports (not hardcoded), and that a dashboard is provisioned.
  grafanaDatasourcesTest = pkgs.runCommand "test-grafana-datasources" {} ''
    echo "=== Testing Grafana Datasource Provisioning ==="

    SCRIPT=${grafanaEnabledScript}
    INI=$(grep -o -- '--config /nix/store/[^ ]*' "$SCRIPT" | head -1 | cut -d' ' -f2)
    PROVISIONING=$(grep -o 'provisioning = /nix/store/[^ ]*' "$INI" | head -1 | cut -d' ' -f3)

    if grep -rq '"url":"http://127.0.0.1:9091"' "$PROVISIONING/datasources"; then
      echo "  Prometheus datasource url derived from myConfig.prometheus.port (9091): OK"
    else
      echo "  FAIL: Prometheus datasource should target http://127.0.0.1:9091"; exit 1
    fi

    if grep -rq '"url":"http://127.0.0.1:3101"' "$PROVISIONING/datasources"; then
      echo "  Loki datasource url derived from myConfig.loki.port (3101): OK"
    else
      echo "  FAIL: Loki datasource should target http://127.0.0.1:3101"; exit 1
    fi

    if grep -rlq '"type":"prometheus"' "$PROVISIONING/datasources" > /dev/null && \
       grep -rlq '"type":"loki"' "$PROVISIONING/datasources" > /dev/null; then
      echo "  both prometheus and loki datasource types present: OK"
    else
      echo "  FAIL: both prometheus and loki datasource types should be present"; exit 1
    fi

    DASHBOARDS_DIR=$(grep -o '"path":"/nix/store/[^"]*"' "$PROVISIONING/dashboards/dashboards.yml" | head -1 | sed 's/"path":"//;s/"$//')
    DASHBOARD_COUNT=$(find "$DASHBOARDS_DIR" -name '*.json' | wc -l | tr -d ' ')
    if [ "$DASHBOARD_COUNT" -ge 1 ]; then
      echo "  at least one dashboard provisioned ($DASHBOARD_COUNT found): OK"
    else
      echo "  FAIL: at least one dashboard JSON should be provisioned"; exit 1
    fi

    echo "All Grafana datasource provisioning tests passed"
    touch $out
  '';
}
