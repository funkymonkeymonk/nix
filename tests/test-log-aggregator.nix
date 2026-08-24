# Log aggregator tests (Vector + Loki) for NixOS
#
# Verifies:
#   - modules/nixos/vector.nix option defaults and enabled-state wiring
#     (services.vector.enable, journald source, host/service/severity labels
#     on the Loki sink)
#   - modules/nixos/loki.nix option defaults and enabled-state wiring
#     (services.loki.enable, configured HTTP port, firewall behavior)
#   - type-server actually enables both modules (via the real flake config)
{
  pkgs,
  self ? null,
  ...
}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  vectorStubs = stubs.base ++ stubs.nixosService ++ [../modules/nixos/vector.nix];
  lokiStubs = stubs.base ++ stubs.nixosService ++ [../modules/nixos/loki.nix];

  vectorDefaults =
    (lib.evalModules {
      modules = vectorStubs;
    }).config.myConfig.vector;

  vectorEnabled =
    (lib.evalModules {
      modules =
        vectorStubs
        ++ [
          {
            config.networking.hostName = "type-server";
            config.myConfig.vector.enable = true;
          }
        ];
    }).config;

  vectorCustomEndpoint =
    (lib.evalModules {
      modules =
        vectorStubs
        ++ [
          {
            config.networking.hostName = "type-server";
            config.myConfig.vector = {
              enable = true;
              lokiEndpoint = "http://loki.internal:3100";
            };
          }
        ];
    }).config;

  lokiDefaults =
    (lib.evalModules {
      modules = lokiStubs;
    }).config.myConfig.loki;

  lokiEnabled =
    (lib.evalModules {
      modules =
        lokiStubs
        ++ [
          {config.myConfig.loki.enable = true;}
        ];
    }).config;

  lokiEnabledWithFirewall =
    (lib.evalModules {
      modules =
        lokiStubs
        ++ [
          {
            config.myConfig.loki = {
              enable = true;
              openFirewall = true;
              port = 3101;
            };
          }
        ];
    }).config;

  vectorSettings = vectorEnabled.services.vector.settings;
  lokiLabels = vectorSettings.sinks.loki.labels;

  # Real flake wiring: type-server must actually enable both modules.
  typeServerConfig =
    if self != null
    then self.nixosConfigurations.type-server.config
    else null;
in {
  vectorOptionsTest = pkgs.runCommand "test-vector-options" {} ''
    echo "=== Testing Vector Option Defaults ==="

    ${
      if !vectorDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  FAIL: enable should default to false"; exit 1''
    }

    ${
      if vectorDefaults.lokiEndpoint == "http://localhost:3100"
      then ''echo "  lokiEndpoint default = http://localhost:3100: OK"''
      else ''echo "  FAIL: lokiEndpoint should default to http://localhost:3100"; exit 1''
    }

    echo "All Vector option default tests passed"
    touch $out
  '';

  vectorEnabledTest = pkgs.runCommand "test-vector-enabled" {} ''
    echo "=== Testing Vector Enabled Wiring ==="

    ${
      if vectorEnabled.services.vector.enable
      then ''echo "  services.vector.enable = true: OK"''
      else ''echo "  FAIL: services.vector.enable should be true"; exit 1''
    }

    ${
      if vectorEnabled.services.vector.journaldAccess
      then ''echo "  journaldAccess = true: OK"''
      else ''echo "  FAIL: journaldAccess should be true"; exit 1''
    }

    ${
      if vectorSettings.sources.journald.type == "journald"
      then ''echo "  sources.journald configured: OK"''
      else ''echo "  FAIL: sources.journald should be configured"; exit 1''
    }

    ${
      if vectorSettings.sinks.loki.type == "loki"
      then ''echo "  sinks.loki configured: OK"''
      else ''echo "  FAIL: sinks.loki should be configured"; exit 1''
    }

    ${
      if vectorSettings.sinks.loki.endpoint == "http://localhost:3100"
      then ''echo "  sinks.loki.endpoint default: OK"''
      else ''echo "  FAIL: sinks.loki.endpoint should default to http://localhost:3100"; exit 1''
    }

    # Acceptance criteria: log labels host, service, severity
    ${
      if lokiLabels.host == "type-server"
      then ''echo "  label 'host' = type-server: OK"''
      else ''echo "  FAIL: label 'host' should equal the configured hostName"; exit 1''
    }

    ${
      if lokiLabels.service == "{{ service }}"
      then ''echo "  label 'service' templated from event field: OK"''
      else ''echo "  FAIL: label 'service' should template the per-event service field"; exit 1''
    }

    ${
      if lokiLabels.severity == "{{ severity }}"
      then ''echo "  label 'severity' templated from event field: OK"''
      else ''echo "  FAIL: label 'severity' should template the per-event severity field"; exit 1''
    }

    echo "All Vector enabled wiring tests passed"
    touch $out
  '';

  vectorCustomEndpointTest = pkgs.runCommand "test-vector-custom-endpoint" {} ''
    echo "=== Testing Vector Custom Loki Endpoint ==="

    ${
      if vectorCustomEndpoint.services.vector.settings.sinks.loki.endpoint == "http://loki.internal:3100"
      then ''echo "  custom lokiEndpoint wired to sink: OK"''
      else ''echo "  FAIL: custom lokiEndpoint should be wired to sinks.loki.endpoint"; exit 1''
    }

    echo "All Vector custom endpoint tests passed"
    touch $out
  '';

  lokiOptionsTest = pkgs.runCommand "test-loki-options" {} ''
    echo "=== Testing Loki Option Defaults ==="

    ${
      if !lokiDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  FAIL: enable should default to false"; exit 1''
    }

    ${
      if lokiDefaults.port == 3100
      then ''echo "  port default = 3100: OK"''
      else ''echo "  FAIL: port should default to 3100"; exit 1''
    }

    ${
      if !lokiDefaults.openFirewall
      then ''echo "  openFirewall default = false: OK"''
      else ''echo "  FAIL: openFirewall should default to false"; exit 1''
    }

    echo "All Loki option default tests passed"
    touch $out
  '';

  lokiEnabledTest = pkgs.runCommand "test-loki-enabled" {} ''
    echo "=== Testing Loki Enabled Wiring ==="

    ${
      if lokiEnabled.services.loki.enable
      then ''echo "  services.loki.enable = true: OK"''
      else ''echo "  FAIL: services.loki.enable should be true"; exit 1''
    }

    ${
      if lokiEnabled.services.loki.configuration.server.http_listen_port == 3100
      then ''echo "  configuration.server.http_listen_port = 3100: OK"''
      else ''echo "  FAIL: http_listen_port should be 3100"; exit 1''
    }

    ${
      if lokiEnabled.services.loki.configuration.auth_enabled == false
      then ''echo "  auth_enabled = false (single-tenant): OK"''
      else ''echo "  FAIL: auth_enabled should be false"; exit 1''
    }

    ${
      if !(builtins.elem 3100 lokiEnabled.networking.firewall.allowedTCPPorts or [])
      then ''echo "  firewall NOT opened by default: OK"''
      else ''echo "  FAIL: firewall should not be opened when openFirewall = false"; exit 1''
    }

    echo "All Loki enabled wiring tests passed"
    touch $out
  '';

  lokiFirewallTest = pkgs.runCommand "test-loki-firewall" {} ''
    echo "=== Testing Loki openFirewall + custom port ==="

    ${
      if lokiEnabledWithFirewall.services.loki.configuration.server.http_listen_port == 3101
      then ''echo "  custom port wired to configuration: OK"''
      else ''echo "  FAIL: custom port should be wired to configuration.server.http_listen_port"; exit 1''
    }

    ${
      if builtins.elem 3101 lokiEnabledWithFirewall.networking.firewall.allowedTCPPorts
      then ''echo "  firewall opened on custom port when openFirewall = true: OK"''
      else ''echo "  FAIL: firewall should be opened on the configured port"; exit 1''
    }

    echo "All Loki firewall tests passed"
    touch $out
  '';

  # Real target wiring: only runs when `self` is available (skipped for
  # `nix-unit`/isolated invocations that don't pass a flake `self`).
  typeServerLogAggregatorTest =
    if typeServerConfig == null
    then
      pkgs.runCommand "test-type-server-log-aggregator-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else
      pkgs.runCommand "test-type-server-log-aggregator" {} ''
        echo "=== Testing type-server Log Aggregator Wiring ==="

        ${
          if typeServerConfig.myConfig.vector.enable
          then ''echo "  myConfig.vector.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should enable myConfig.vector"; exit 1''
        }

        ${
          if typeServerConfig.myConfig.loki.enable
          then ''echo "  myConfig.loki.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should enable myConfig.loki"; exit 1''
        }

        ${
          if typeServerConfig.services.vector.enable
          then ''echo "  services.vector.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should have services.vector.enable = true"; exit 1''
        }

        ${
          if typeServerConfig.services.loki.enable
          then ''echo "  services.loki.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should have services.loki.enable = true"; exit 1''
        }

        echo "All type-server log aggregator wiring tests passed"
        touch $out
      '';
}
