# Prometheus + Alertmanager observability tests for NixOS (type-server)
#
# Verifies:
#   - modules/nixos/prometheus.nix option defaults and enabled-state wiring
#     (services.prometheus.enable, node-exporter scrape target, basic alert
#     rules for disk/memory/service-down, alertmanagers wiring, tailscale-only
#     firewall opt-in for federation)
#   - modules/nixos/alertmanager.nix option defaults and enabled-state wiring
#     (services.prometheus.alertmanager.enable, documented null-receiver
#     placeholder, optional webhook receiver)
#   - type-server actually enables Prometheus, node_exporter, and
#     Alertmanager (via the real flake config) — and does NOT run Grafana,
#     per the federation decision documented in the PR description.
{
  pkgs,
  self ? null,
  ...
}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  prometheusStubs = stubs.base ++ stubs.nixosService ++ [../modules/nixos/prometheus.nix];
  alertmanagerStubs = stubs.base ++ stubs.nixosService ++ [../modules/nixos/alertmanager.nix];

  prometheusDefaults =
    (lib.evalModules {
      modules = prometheusStubs;
    }).config.myConfig.prometheus;

  nodeExporterDefaults =
    (lib.evalModules {
      modules = prometheusStubs;
    }).config.myConfig.nodeExporter;

  prometheusEnabled =
    (lib.evalModules {
      modules =
        prometheusStubs
        ++ [
          {
            config.myConfig.prometheus.enable = true;
            config.myConfig.nodeExporter.enable = true;
          }
        ];
    }).config;

  prometheusEnabledNoNodeExporter =
    (lib.evalModules {
      modules =
        prometheusStubs
        ++ [
          {config.myConfig.prometheus.enable = true;}
        ];
    }).config;

  prometheusWithFirewall =
    (lib.evalModules {
      modules =
        prometheusStubs
        ++ [
          {
            config.myConfig.prometheus = {
              enable = true;
              port = 9091;
              openFirewallTailscale = true;
            };
          }
        ];
    }).config;

  # Alertmanager wiring: prometheus module wires services.prometheus.alertmanagers
  # only when myConfig.alertmanager.enable is set — stub that option here since
  # it's declared by the (separate) alertmanager module.
  alertmanagerOptionStub = {
    options.myConfig.alertmanager = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 9093;
      };
    };
  };

  prometheusWithAlertmanager =
    (lib.evalModules {
      modules =
        prometheusStubs
        ++ [
          alertmanagerOptionStub
          {
            config.myConfig.prometheus.enable = true;
            config.myConfig.alertmanager.enable = true;
          }
        ];
    }).config;

  alertmanagerDefaults =
    (lib.evalModules {
      modules = alertmanagerStubs;
    }).config.myConfig.alertmanager;

  alertmanagerEnabled =
    (lib.evalModules {
      modules =
        alertmanagerStubs
        ++ [
          {config.myConfig.alertmanager.enable = true;}
        ];
    }).config;

  alertmanagerWithWebhook =
    (lib.evalModules {
      modules =
        alertmanagerStubs
        ++ [
          {
            config.myConfig.alertmanager = {
              enable = true;
              receiverWebhookUrl = "https://example.invalid/webhook";
            };
          }
        ];
    }).config;

  rulesText = builtins.head prometheusEnabled.services.prometheus.rules;

  # Real target wiring: only runs when `self` is available (skipped for
  # `nix-unit`/isolated invocations that don't pass a flake `self`).
  typeServerConfig =
    if self != null
    then self.nixosConfigurations.type-server.config
    else null;
in {
  prometheusOptionsTest = pkgs.runCommand "test-nixos-prometheus-options" {} ''
    echo "=== Testing NixOS Prometheus Option Defaults ==="

    ${
      if !prometheusDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  FAIL: enable should default to false"; exit 1''
    }

    ${
      if prometheusDefaults.port == 9090
      then ''echo "  port default = 9090: OK"''
      else ''echo "  FAIL: port should default to 9090"; exit 1''
    }

    ${
      if prometheusDefaults.retention == "15d"
      then ''echo "  retention default = 15d: OK"''
      else ''echo "  FAIL: retention should default to 15d"; exit 1''
    }

    ${
      if !prometheusDefaults.openFirewallTailscale
      then ''echo "  openFirewallTailscale default = false: OK"''
      else ''echo "  FAIL: openFirewallTailscale should default to false"; exit 1''
    }

    echo "All NixOS Prometheus option default tests passed"
    touch $out
  '';

  nodeExporterOptionsTest = pkgs.runCommand "test-nixos-node-exporter-options" {} ''
    echo "=== Testing NixOS node_exporter Option Defaults ==="

    ${
      if !nodeExporterDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  FAIL: enable should default to false"; exit 1''
    }

    ${
      if nodeExporterDefaults.port == 9100
      then ''echo "  port default = 9100: OK"''
      else ''echo "  FAIL: port should default to 9100"; exit 1''
    }

    echo "All NixOS node_exporter option default tests passed"
    touch $out
  '';

  prometheusEnabledTest = pkgs.runCommand "test-nixos-prometheus-enabled" {} ''
    echo "=== Testing NixOS Prometheus Enabled Wiring ==="

    ${
      if prometheusEnabled.services.prometheus.enable
      then ''echo "  services.prometheus.enable = true: OK"''
      else ''echo "  FAIL: services.prometheus.enable should be true"; exit 1''
    }

    ${
      if prometheusEnabled.services.prometheus.exporters.node.enable
      then ''echo "  services.prometheus.exporters.node.enable = true: OK"''
      else ''echo "  FAIL: services.prometheus.exporters.node.enable should be true"; exit 1''
    }

    ${
      if lib.any (sc: sc.job_name == "node") prometheusEnabled.services.prometheus.scrapeConfigs
      then ''echo "  scrapeConfigs includes 'node' job: OK"''
      else ''echo "  FAIL: scrapeConfigs should include a 'node' job for node_exporter"; exit 1''
    }

    ${
      if lib.any (sc: sc.job_name == "prometheus") prometheusEnabled.services.prometheus.scrapeConfigs
      then ''echo "  scrapeConfigs includes self-scrape 'prometheus' job: OK"''
      else ''echo "  FAIL: scrapeConfigs should include a self-scrape 'prometheus' job"; exit 1''
    }

    ${
      if !(lib.any (sc: sc.job_name == "node") prometheusEnabledNoNodeExporter.services.prometheus.scrapeConfigs)
      then ''echo "  'node' scrape target omitted when node_exporter disabled: OK"''
      else ''echo "  FAIL: 'node' scrape target should be omitted when myConfig.nodeExporter.enable is false"; exit 1''
    }

    echo "All NixOS Prometheus enabled wiring tests passed"
    touch $out
  '';

  prometheusAlertRulesTest = pkgs.runCommand "test-nixos-prometheus-alert-rules" {} ''
    echo "=== Testing NixOS Prometheus Basic Alert Rules ==="

    ${
      if builtins.length prometheusEnabled.services.prometheus.rules > 0
      then ''echo "  services.prometheus.rules is non-empty: OK"''
      else ''echo "  FAIL: services.prometheus.rules should not be empty"; exit 1''
    }

    ${
      if lib.hasInfix "PrometheusTargetDown" rulesText
      then ''echo "  alert rule for service-down (PrometheusTargetDown) present: OK"''
      else ''echo "  FAIL: rules should include a service-down alert (PrometheusTargetDown)"; exit 1''
    }

    ${
      if lib.hasInfix "HostHighMemoryUsage" rulesText
      then ''echo "  alert rule for memory (HostHighMemoryUsage) present: OK"''
      else ''echo "  FAIL: rules should include a memory alert (HostHighMemoryUsage)"; exit 1''
    }

    ${
      if lib.hasInfix "HostOutOfDiskSpace" rulesText
      then ''echo "  alert rule for disk (HostOutOfDiskSpace) present: OK"''
      else ''echo "  FAIL: rules should include a disk alert (HostOutOfDiskSpace)"; exit 1''
    }

    echo "All NixOS Prometheus alert rule tests passed"
    touch $out
  '';

  prometheusAlertmanagerWiringTest = pkgs.runCommand "test-nixos-prometheus-alertmanager-wiring" {} ''
    echo "=== Testing NixOS Prometheus -> Alertmanager Wiring ==="

    ${
      if lib.any (am: builtins.elem "localhost:9093" (builtins.elemAt am.static_configs 0).targets) prometheusWithAlertmanager.services.prometheus.alertmanagers
      then ''echo "  alertmanagers target localhost:9093 when myConfig.alertmanager.enable: OK"''
      else ''echo "  FAIL: alertmanagers should target localhost:9093 when myConfig.alertmanager.enable"; exit 1''
    }

    ${
      if prometheusEnabledNoNodeExporter.services.prometheus.alertmanagers == []
      then ''echo "  alertmanagers empty when myConfig.alertmanager.enable is false: OK"''
      else ''echo "  FAIL: alertmanagers should be empty when myConfig.alertmanager.enable is false"; exit 1''
    }

    echo "All NixOS Prometheus->Alertmanager wiring tests passed"
    touch $out
  '';

  prometheusFirewallTest = pkgs.runCommand "test-nixos-prometheus-firewall" {} ''
    echo "=== Testing NixOS Prometheus Tailscale-only Firewall Opt-in ==="

    ${
      if !(builtins.elem 9090 (prometheusEnabled.networking.firewall.interfaces.tailscale0.allowedTCPPorts or []))
      then ''echo "  tailscale0 firewall NOT opened by default: OK"''
      else ''echo "  FAIL: firewall should not be opened when openFirewallTailscale = false"; exit 1''
    }

    ${
      if builtins.elem 9091 prometheusWithFirewall.networking.firewall.interfaces.tailscale0.allowedTCPPorts
      then ''echo "  tailscale0 firewall opened on configured port when openFirewallTailscale = true: OK"''
      else ''echo "  FAIL: firewall should open the configured port on tailscale0 when openFirewallTailscale = true"; exit 1''
    }

    echo "All NixOS Prometheus firewall tests passed"
    touch $out
  '';

  alertmanagerOptionsTest = pkgs.runCommand "test-nixos-alertmanager-options" {} ''
    echo "=== Testing NixOS Alertmanager Option Defaults ==="

    ${
      if !alertmanagerDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  FAIL: enable should default to false"; exit 1''
    }

    ${
      if alertmanagerDefaults.port == 9093
      then ''echo "  port default = 9093: OK"''
      else ''echo "  FAIL: port should default to 9093"; exit 1''
    }

    ${
      if alertmanagerDefaults.receiverWebhookUrl == null
      then ''echo "  receiverWebhookUrl default = null: OK"''
      else ''echo "  FAIL: receiverWebhookUrl should default to null"; exit 1''
    }

    echo "All NixOS Alertmanager option default tests passed"
    touch $out
  '';

  alertmanagerNullReceiverTest = pkgs.runCommand "test-nixos-alertmanager-null-receiver" {} ''
    echo "=== Testing NixOS Alertmanager Null-Receiver Placeholder ==="

    ${
      if alertmanagerEnabled.services.prometheus.alertmanager.enable
      then ''echo "  services.prometheus.alertmanager.enable = true: OK"''
      else ''echo "  FAIL: services.prometheus.alertmanager.enable should be true"; exit 1''
    }

    ${
      if alertmanagerEnabled.services.prometheus.alertmanager.configuration.route.receiver == "null-receiver"
      then ''echo "  route.receiver = null-receiver (no webhook configured): OK"''
      else ''echo "  FAIL: route.receiver should default to null-receiver"; exit 1''
    }

    ${
      if builtins.length alertmanagerEnabled.services.prometheus.alertmanager.configuration.receivers == 1
      then ''echo "  exactly one receiver (null-receiver) when no webhook configured: OK"''
      else ''echo "  FAIL: should have exactly one receiver when receiverWebhookUrl is null"; exit 1''
    }

    ${
      if builtins.length alertmanagerWithWebhook.services.prometheus.alertmanager.configuration.receivers == 2
      then ''echo "  webhook-receiver added alongside null-receiver when receiverWebhookUrl set: OK"''
      else ''echo "  FAIL: should have two receivers when receiverWebhookUrl is set"; exit 1''
    }

    echo "All NixOS Alertmanager null-receiver tests passed"
    touch $out
  '';

  # Real target wiring: only runs when `self` is available (skipped for
  # `nix-unit`/isolated invocations that don't pass a flake `self`).
  typeServerObservabilityTest =
    if typeServerConfig == null
    then
      pkgs.runCommand "test-type-server-observability-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else
      pkgs.runCommand "test-type-server-observability" {} ''
        echo "=== Testing type-server Observability Stack Wiring ==="

        ${
          if typeServerConfig.myConfig.prometheus.enable
          then ''echo "  myConfig.prometheus.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should enable myConfig.prometheus"; exit 1''
        }

        ${
          if typeServerConfig.myConfig.nodeExporter.enable
          then ''echo "  myConfig.nodeExporter.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should enable myConfig.nodeExporter"; exit 1''
        }

        ${
          if typeServerConfig.myConfig.alertmanager.enable
          then ''echo "  myConfig.alertmanager.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should enable myConfig.alertmanager"; exit 1''
        }

        ${
          if typeServerConfig.services.prometheus.enable
          then ''echo "  services.prometheus.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should have services.prometheus.enable = true"; exit 1''
        }

        ${
          if typeServerConfig.services.prometheus.exporters.node.enable
          then ''echo "  services.prometheus.exporters.node.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should have services.prometheus.exporters.node.enable = true"; exit 1''
        }

        ${
          if typeServerConfig.services.prometheus.alertmanager.enable
          then ''echo "  services.prometheus.alertmanager.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should have services.prometheus.alertmanager.enable = true"; exit 1''
        }

        # Federation decision: type-server runs NO Grafana of its own (see PR
        # description). Its Prometheus is intended to be federated as a second
        # datasource by darwin-server's Grafana (PR #432) over Tailscale.
        ${
          if !(typeServerConfig.myConfig.grafana.enable or false)
          then ''echo "  myConfig.grafana.enable is NOT set on type-server (federation, no duplicate Grafana): OK"''
          else ''echo "  FAIL: type-server should not run its own Grafana per the federation decision"; exit 1''
        }

        ${
          if typeServerConfig.myConfig.prometheus.openFirewallTailscale
          then ''echo "  myConfig.prometheus.openFirewallTailscale = true on type-server (federation-ready): OK"''
          else ''echo "  FAIL: type-server should open Prometheus on tailscale0 for federation"; exit 1''
        }

        echo "All type-server observability wiring tests passed"
        touch $out
      '';
}
