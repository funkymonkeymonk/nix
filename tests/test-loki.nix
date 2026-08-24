# Loki log aggregation option tests
# Validates option defaults, custom values, and generated config for
# modules/services/loki/darwin.nix (uses the pkgs.grafana-loki package —
# NOT pkgs.loki, which is an unrelated C++ library).
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  lokiDefaults =
    (lib.evalModules {
      modules = stubs.loki;
    }).config.myConfig.loki;

  lokiCustom =
    (lib.evalModules {
      modules =
        stubs.loki
        ++ [
          {
            config.myConfig.users = [{name = "monkey";}];
            config.myConfig.loki = {
              enable = true;
              port = 3101;
              bindAddress = "192.168.83.20";
              retention = "72h";
            };
          }
        ];
    }).config;

  lokiEnabledScript = lokiCustom.launchd.daemons.loki.command;
in {
  lokiOptionsTest = pkgs.runCommand "test-loki-options" {} ''
    echo "=== Testing Loki Option Defaults ==="

    ${
      if !lokiDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if lokiDefaults.port == 3100
      then ''echo "  port default = 3100: OK"''
      else ''echo "  port should default to 3100!"; exit 1''
    }

    ${
      if lokiDefaults.bindAddress == "127.0.0.1"
      then ''echo "  bindAddress default = 127.0.0.1 (loopback-only, safe default): OK"''
      else ''echo "  bindAddress should default to 127.0.0.1!"; exit 1''
    }

    ${
      if lokiDefaults.retention == "168h"
      then ''echo "  retention default = 168h (7 days): OK"''
      else ''echo "  retention should default to 168h!"; exit 1''
    }

    echo "All Loki option defaults verified"
    touch $out
  '';

  lokiCustomOptionsTest = pkgs.runCommand "test-loki-custom-options" {} ''
    echo "=== Testing Loki Custom Options ==="

    ${
      if lokiCustom.myConfig.loki.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if lokiCustom.myConfig.loki.port == 3101
      then ''echo "  port = 3101: OK"''
      else ''echo "  port should be 3101!"; exit 1''
    }

    ${
      if lokiCustom.myConfig.loki.bindAddress == "192.168.83.20"
      then ''echo "  bindAddress = 192.168.83.20: OK"''
      else ''echo "  bindAddress should be 192.168.83.20!"; exit 1''
    }

    echo "All Loki custom options verified"
    touch $out
  '';

  # Verify the generated Loki config sets the configured listen address/port
  # and a 7-day (or custom) retention policy via the compactor.
  lokiGeneratedConfigTest = pkgs.runCommand "test-loki-generated-config" {} ''
    echo "=== Testing Loki Generated Config ==="

    SCRIPT=${lokiEnabledScript}
    CONFIG=$(grep -o -- '-config.file /nix/store/[^ ]*' "$SCRIPT" | head -1 | cut -d' ' -f2)

    if grep -q '"http_listen_address":"192.168.83.20"' "$CONFIG"; then
      echo "  http_listen_address = 192.168.83.20: OK"
    else
      echo "  FAIL: config should set http_listen_address to 192.168.83.20"; exit 1
    fi

    if grep -q '"http_listen_port":3101' "$CONFIG"; then
      echo "  http_listen_port = 3101: OK"
    else
      echo "  FAIL: config should set http_listen_port to 3101"; exit 1
    fi

    if grep -q '"retention_period":"72h"' "$CONFIG"; then
      echo "  retention_period = 72h: OK"
    else
      echo "  FAIL: config should set retention_period to 72h"; exit 1
    fi

    if grep -q '"retention_enabled":true' "$CONFIG"; then
      echo "  compactor retention_enabled = true: OK"
    else
      echo "  FAIL: compactor should have retention_enabled: true"; exit 1
    fi

    echo "All Loki generated config tests passed"
    touch $out
  '';
}
