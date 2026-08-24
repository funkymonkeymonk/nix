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

  # Federation: type-server (a NixOS host) runs its own Prometheus +
  # node_exporter + Alertmanager but no Grafana of its own (see
  # modules/nixos/prometheus.nix and this PR's description for the
  # decision). Instead, darwin-server's Grafana can add type-server's
  # Prometheus as a second datasource over Tailscale.
  grafanaFederated =
    (lib.evalModules {
      modules =
        stubs.grafana
        ++ [
          {
            config.myConfig.users = [{name = "monkey";}];
            config.myConfig.grafana = {
              enable = true;
              typeServerPrometheusUrl = "http://type-server.tailnet.ts.net:9090";
            };
          }
        ];
    }).config;

  grafanaFederatedScript = grafanaFederated.launchd.daemons.grafana.command;
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

  # Federated type-server Prometheus datasource: off by default (no known
  # Tailscale address to guess), addable via typeServerPrometheusUrl.
  grafanaFederatedDatasourceTest = pkgs.runCommand "test-grafana-federated-datasource" {} ''
    echo "=== Testing Grafana Federated type-server Datasource ==="

    ${
      if grafanaDefaults.typeServerPrometheusUrl == null
      then ''echo "  typeServerPrometheusUrl default = null (no federation until configured): OK"''
      else ''echo "  FAIL: typeServerPrometheusUrl should default to null"; exit 1''
    }

    DEFAULT_SCRIPT=${grafanaCustom.launchd.daemons.grafana.command}
    DEFAULT_INI=$(grep -o -- '--config /nix/store/[^ ]*' "$DEFAULT_SCRIPT" | head -1 | cut -d' ' -f2)
    DEFAULT_PROVISIONING=$(grep -o 'provisioning = /nix/store/[^ ]*' "$DEFAULT_INI" | head -1 | cut -d' ' -f3)

    if grep -rq 'type-server' "$DEFAULT_PROVISIONING/datasources"; then
      echo "  FAIL: no type-server datasource should be provisioned when typeServerPrometheusUrl is null"; exit 1
    else
      echo "  no type-server datasource provisioned by default: OK"
    fi

    FED_SCRIPT=${grafanaFederatedScript}
    FED_INI=$(grep -o -- '--config /nix/store/[^ ]*' "$FED_SCRIPT" | head -1 | cut -d' ' -f2)
    FED_PROVISIONING=$(grep -o 'provisioning = /nix/store/[^ ]*' "$FED_INI" | head -1 | cut -d' ' -f3)

    if grep -rq '"url":"http://type-server.tailnet.ts.net:9090"' "$FED_PROVISIONING/datasources"; then
      echo "  federated type-server Prometheus datasource url wired: OK"
    else
      echo "  FAIL: federated datasource should target http://type-server.tailnet.ts.net:9090"; exit 1
    fi

    if grep -rq '"name":"Prometheus (type-server)"' "$FED_PROVISIONING/datasources"; then
      echo "  federated datasource named 'Prometheus (type-server)': OK"
    else
      echo "  FAIL: federated datasource should be named 'Prometheus (type-server)'"; exit 1
    fi

    echo "All Grafana federated datasource tests passed"
    touch $out
  '';
}
