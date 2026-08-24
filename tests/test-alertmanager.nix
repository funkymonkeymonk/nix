# Alertmanager option tests
# Validates option defaults, custom values, and the placeholder null
# receiver for modules/services/alertmanager/darwin.nix.
#
# Alertmanager's actual notification receiver (Matrix/Discord webhook) is
# genuinely TBD — no credentials are available yet. This module wires up
# Alertmanager itself with a documented null receiver placeholder; see the
# `receiverWebhookUrl` option below.
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  alertmanagerDefaults =
    (lib.evalModules {
      modules = stubs.alertmanager;
    }).config.myConfig.alertmanager;

  alertmanagerCustom =
    (lib.evalModules {
      modules =
        stubs.alertmanager
        ++ [
          {
            config.myConfig.users = [{name = "monkey";}];
            config.myConfig.alertmanager = {
              enable = true;
              port = 9094;
              bindAddress = "192.168.83.20";
            };
          }
        ];
    }).config;

  alertmanagerEnabledScript = alertmanagerCustom.launchd.daemons.alertmanager.command;
in {
  alertmanagerOptionsTest = pkgs.runCommand "test-alertmanager-options" {} ''
    echo "=== Testing Alertmanager Option Defaults ==="

    ${
      if !alertmanagerDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if alertmanagerDefaults.port == 9093
      then ''echo "  port default = 9093: OK"''
      else ''echo "  port should default to 9093!"; exit 1''
    }

    ${
      if alertmanagerDefaults.bindAddress == "127.0.0.1"
      then ''echo "  bindAddress default = 127.0.0.1: OK"''
      else ''echo "  bindAddress should default to 127.0.0.1!"; exit 1''
    }

    ${
      if alertmanagerDefaults.receiverWebhookUrl == null
      then ''echo "  receiverWebhookUrl default = null (TBD placeholder): OK"''
      else ''echo "  receiverWebhookUrl should default to null!"; exit 1''
    }

    echo "All Alertmanager option defaults verified"
    touch $out
  '';

  alertmanagerCustomOptionsTest = pkgs.runCommand "test-alertmanager-custom-options" {} ''
    echo "=== Testing Alertmanager Custom Options ==="

    ${
      if alertmanagerCustom.myConfig.alertmanager.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if alertmanagerCustom.myConfig.alertmanager.port == 9094
      then ''echo "  port = 9094: OK"''
      else ''echo "  port should be 9094!"; exit 1''
    }

    echo "All Alertmanager custom options verified"
    touch $out
  '';

  # Verify the generated alertmanager.yml uses a documented null receiver
  # placeholder when no webhook URL is configured, rather than guessing
  # credentials.
  alertmanagerNullReceiverTest = pkgs.runCommand "test-alertmanager-null-receiver" {} ''
    echo "=== Testing Alertmanager Null Receiver Placeholder ==="

    SCRIPT=${alertmanagerEnabledScript}
    CONFIG=$(grep -o -- '--config.file /nix/store/[^ ]*' "$SCRIPT" | head -1 | cut -d' ' -f2)

    if grep -q '"name":"null-receiver"' "$CONFIG"; then
      echo "  null-receiver present: OK"
    else
      echo "  FAIL: config should define a null-receiver"; exit 1
    fi

    if grep -q '"receiver":"null-receiver"' "$CONFIG"; then
      echo "  route defaults to null-receiver: OK"
    else
      echo "  FAIL: route should default to null-receiver"; exit 1
    fi

    if grep -q 'webhook_configs' "$CONFIG"; then
      echo "  FAIL: no webhook should be configured without a real URL"; exit 1
    else
      echo "  no webhook configured (TBD, as expected): OK"
    fi

    echo "All Alertmanager null receiver tests passed"
    touch $out
  '';
}
