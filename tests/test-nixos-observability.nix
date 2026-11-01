# Prometheus + Alertmanager observability tests for NixOS (type-server)
#
# Verifies:
#   - modules/nixos/prometheus.nix option defaults and enabled-state wiring
#     (services.prometheus.enable, node-exporter scrape target, basic alert
#     rules for disk/memory/service-down, alertmanagers wiring, restricted
#     Tailscale-only firewall opt-in)
#   - modules/nixos/alertmanager.nix option defaults and enabled-state wiring
#     (services.prometheus.alertmanager.enable, documented null-receiver
#     placeholder, optional webhook receiver)
#   - type-server keeps node_exporter enabled but does not run local backend
#     services (Prometheus, Alertmanager, or Grafana).
{
  pkgs,
  self ? null,
  inputs ? {},
  ...
}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  prometheusStubs = stubs.base ++ stubs.nixosService ++ [../modules/nixos/prometheus.nix];
  alertmanagerStubs = stubs.base ++ stubs.nixosService ++ [../modules/nixos/alertmanager.nix];
  observabilityBackendStubs =
    stubs.base
    ++ stubs.onepassword
    ++ stubs.nixosGrafanaService
    ++ [../library/archetypes/type-observability.nix];
  evalPrometheus = {
    modules,
    nodeExporterInventory ? [],
  }:
    lib.evalModules {
      specialArgs = {inherit nodeExporterInventory;};
      inherit modules;
    };

  prometheusDefaults =
    (evalPrometheus {
      modules = prometheusStubs;
    }).config.myConfig.prometheus;

  nodeExporterDefaults =
    (evalPrometheus {
      modules = prometheusStubs;
    }).config.myConfig.nodeExporter;

  prometheusEnabled =
    (evalPrometheus {
      nodeExporterInventory = [
        {
          name = "test-node";
          target = "test-node.example:9100";
        }
      ];
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
    (evalPrometheus {
      modules =
        prometheusStubs
        ++ [
          {config.myConfig.prometheus.enable = true;}
        ];
    }).config;

  prometheusWithFirewall =
    (evalPrometheus {
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

  nodeExporterWithCustomFirewall =
    (evalPrometheus {
      modules =
        prometheusStubs
        ++ [
          {
            config.myConfig.nodeExporter = {
              enable = true;
              port = 9101;
              openFirewallInterfaces = ["enp3s0"];
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
    (evalPrometheus {
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

  observabilityBackend =
    (lib.evalModules {
      specialArgs.nodeExporterInventory = [];
      modules = observabilityBackendStubs;
    }).config;

  centralObservabilityTest =
    if self == null
    then
      pkgs.runCommand "test-central-observability-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else let
      catalog = import ../library/machines/catalog.nix {inherit inputs;};
      inventory = import ../library/machines/observability-inventory.nix {inherit catalog;};
      drlight = self.nixosConfigurations.drlight.config;
      typeServer = self.nixosConfigurations.type-server.config;
      typeServerArm = self.nixosConfigurations.type-server-arm.config;
      typeNas = self.nixosConfigurations.type-nas.config;
      darwinServer = self.darwinConfigurations.darwin-server.config;
      megamanX = self.darwinConfigurations.MegamanX.config;
      scrapeConfig = drlight.services.prometheus.scrapeConfigs;
      nodeScrape = builtins.head (builtins.filter (scrape: scrape.job_name == "node") scrapeConfig);
      selfScrape = builtins.head (builtins.filter (scrape: scrape.job_name == "prometheus") scrapeConfig);
    in
      pkgs.runCommand "test-central-observability" {} ''
        echo "=== Testing central type-observability backend and catalog inventory ==="

        ${
          if observabilityBackend.myConfig.prometheus.enable && observabilityBackend.services.prometheus.enable
          then ''echo "type-observability enables Prometheus: OK"''
          else ''echo "FAIL: type-observability must enable Prometheus"; exit 1''
        }
        ${
          if observabilityBackend.myConfig.loki.enable && observabilityBackend.services.loki.enable
          then ''echo "type-observability enables Loki: OK"''
          else ''echo "FAIL: type-observability must enable Loki"; exit 1''
        }
        ${
          if observabilityBackend.myConfig.loki.openFirewallTailscale
          then ''echo "type-observability enables Loki ingress on tailscale0: OK"''
          else ''echo "FAIL: type-observability must allow remote Vector traffic on tailscale0"; exit 1''
        }
        ${
          if
            builtins.elem observabilityBackend.myConfig.loki.port observabilityBackend.networking.firewall.interfaces.tailscale0.allowedTCPPorts
            && !(builtins.elem observabilityBackend.myConfig.loki.port (observabilityBackend.networking.firewall.allowedTCPPorts or []))
            && !(observabilityBackend.myConfig.loki.openFirewall or false)
          then ''echo "type-observability allows Loki only on tailscale0: OK"''
          else ''echo "FAIL: Loki ingress must be restricted to tailscale0"; exit 1''
        }
        ${
          if observabilityBackend.myConfig.alertmanager.enable && observabilityBackend.services.prometheus.alertmanager.enable
          then ''echo "type-observability enables Alertmanager: OK"''
          else ''echo "FAIL: type-observability must enable Alertmanager"; exit 1''
        }
        ${
          if observabilityBackend.myConfig.grafana.enable && observabilityBackend.services.grafana.enable
          then ''echo "type-observability enables native Grafana: OK"''
          else ''echo "FAIL: type-observability must enable native Grafana"; exit 1''
        }

        ${
          if lib.any (module: lib.hasSuffix "/archetypes/type-observability.nix" (builtins.toString module)) catalog.drlight.modules
          then ''echo "drlight selects type-observability: OK"''
          else ''echo "FAIL: drlight must include type-observability"; exit 1''
        }
        ${
          if drlight.myConfig.prometheus.enable && drlight.myConfig.loki.enable && drlight.myConfig.alertmanager.enable
          then ''echo "drlight backend options are enabled: OK"''
          else ''echo "FAIL: drlight must enable Prometheus, Loki, and Alertmanager"; exit 1''
        }
        ${
          if drlight.services.prometheus.enable && drlight.services.loki.enable && drlight.services.prometheus.alertmanager.enable && drlight.services.grafana.enable
          then ''echo "drlight backend services, including Grafana, are active: OK"''
          else ''echo "FAIL: drlight must run Prometheus, Loki, Alertmanager, and Grafana"; exit 1''
        }
        ${
          if
            builtins.elem drlight.myConfig.loki.port drlight.networking.firewall.interfaces.tailscale0.allowedTCPPorts
            && !(builtins.elem drlight.myConfig.loki.port (drlight.networking.firewall.allowedTCPPorts or []))
            && !(drlight.myConfig.loki.openFirewall or false)
          then ''echo "drlight Loki ingress is Tailscale-only, not global: OK"''
          else ''echo "FAIL: drlight Loki ingress must be restricted to tailscale0"; exit 1''
        }
        ${
          if drlight.myConfig.collector.destinationHostname == "localhost" && drlight.services.loki.enable
          then ''echo "drlight has local Loki receiver for Vector: OK"''
          else ''echo "FAIL: drlight Vector output must have local Loki receiver"; exit 1''
        }

        ${
          if (builtins.head nodeScrape.static_configs).targets == map (target: target.target) inventory.targets
          then ''echo "Prometheus node job uses the full catalog-derived inventory: OK"''
          else ''echo "FAIL: Prometheus node job must use the catalog-derived inventory"; exit 1''
        }
        ${
          if builtins.elem "drlight:9100" (builtins.head nodeScrape.static_configs).targets
          then ''echo "drlight exporter remains in central scrape targets: OK"''
          else ''echo "FAIL: central inventory must include drlight's exporter"; exit 1''
        }
        ${
          if (builtins.head selfScrape.static_configs).targets == ["localhost:9090"]
          then ''echo "Prometheus self-scrape remains configured: OK"''
          else ''echo "FAIL: Prometheus self-scrape must remain configured"; exit 1''
        }
        ${
          if builtins.length drlight.services.prometheus.rules > 0
          then ''echo "central Prometheus alert rules remain configured: OK"''
          else ''echo "FAIL: central Prometheus alert rules must remain configured"; exit 1''
        }

        ${
          if
            typeServer.services.prometheus.enable
            == false
            && typeServer.services.loki.enable == false
            && typeServer.services.prometheus.alertmanager.enable == false
            && !(builtins.elem 3100 (typeServer.networking.firewall.interfaces.tailscale0.allowedTCPPorts or []))
          then ''echo "type-server remains collector-only without Loki ingress: OK"''
          else ''echo "FAIL: type-server must remain collector-only without Loki ingress"; exit 1''
        }
        ${
          if typeServerArm.services.prometheus.enable == false && typeServerArm.services.loki.enable == false && typeServerArm.services.prometheus.alertmanager.enable == false
          then ''echo "type-server-arm remains collector-only: OK"''
          else ''echo "FAIL: type-server-arm must remain collector-only"; exit 1''
        }
        ${
          if typeNas.services.prometheus.enable == false && typeNas.services.loki.enable == false && typeNas.services.prometheus.alertmanager.enable == false
          then ''echo "type-nas remains collector-only: OK"''
          else ''echo "FAIL: type-nas must not run local backends"; exit 1''
        }
        ${
          if (darwinServer.myConfig.prometheus.enable or false) == false && (darwinServer.myConfig.loki.enable or false) == false && (darwinServer.myConfig.alertmanager.enable or false) == false
          then ''echo "darwin-server remains collector-only: OK"''
          else ''echo "FAIL: darwin-server must not run local backends"; exit 1''
        }
        ${
          if (megamanX.myConfig.prometheus.enable or false) == false && (megamanX.myConfig.loki.enable or false) == false && (megamanX.myConfig.alertmanager.enable or false) == false
          then ''echo "MegamanX remains collector-only: OK"''
          else ''echo "FAIL: MegamanX must not run local backends"; exit 1''
        }

        echo "All central observability tests passed"
        touch $out
      '';
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

    ${
      if nodeExporterDefaults.openFirewallInterfaces == ["tailscale0"]
      then ''echo "  exporter firewall defaults to tailscale0 only: OK"''
      else ''echo "  FAIL: exporter firewall should default to tailscale0 only"; exit 1''
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
      let
        nodeJob = builtins.head (builtins.filter (sc: sc.job_name == "node") prometheusEnabled.services.prometheus.scrapeConfigs);
      in
        if (builtins.head nodeJob.static_configs).targets == ["test-node.example:9100"]
        then ''echo "  node scrape job uses projected inventory: OK"''
        else ''echo "  FAIL: node scrape job should use the projected inventory"; exit 1''
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
      then ''echo "  tailscale0 firewall opened on configured Prometheus port: OK"''
      else ''echo "  FAIL: Prometheus firewall should open its configured port on tailscale0"; exit 1''
    }

    ${
      if prometheusEnabled.services.prometheus.exporters.node.listenAddress == "0.0.0.0"
      then ''echo "  node_exporter listens on IPv4 interfaces behind interface firewall: OK"''
      else ''echo "  FAIL: node_exporter should listen on IPv4 interfaces behind the restrictive firewall"; exit 1''
    }

    ${
      if builtins.elem 9100 prometheusEnabled.networking.firewall.interfaces.tailscale0.allowedTCPPorts
      then ''echo "  node_exporter default port allowed on tailscale0: OK"''
      else ''echo "  FAIL: node_exporter should be allowed on tailscale0 by default"; exit 1''
    }

    ${
      if !(builtins.elem 9100 (prometheusEnabled.networking.firewall.allowedTCPPorts or []))
      then ''echo "  node_exporter not opened globally: OK"''
      else ''echo "  FAIL: node_exporter port must not be opened globally"; exit 1''
    }

    ${
      if
        builtins.elem 9101 nodeExporterWithCustomFirewall.networking.firewall.interfaces.enp3s0.allowedTCPPorts
        && !(builtins.elem 9101 (nodeExporterWithCustomFirewall.networking.firewall.interfaces.tailscale0.allowedTCPPorts or []))
        && !(builtins.elem 9101 (nodeExporterWithCustomFirewall.networking.firewall.allowedTCPPorts or []))
      then ''echo "  explicitly configured non-Tailscale interface is the only exporter access path: OK"''
      else ''echo "  FAIL: custom exporter access must be restricted to the configured interface"; exit 1''
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
  typeObservabilityArchetypeTest = pkgs.runCommand "test-type-observability-archetype" {} ''
    echo "=== Testing selected type-observability archetype ==="

    ${
      if observabilityBackend.myConfig.prometheus.enable && observabilityBackend.myConfig.loki.enable && observabilityBackend.myConfig.alertmanager.enable
      then ''echo "all backend options enabled by archetype: OK"''
      else ''echo "FAIL: archetype must enable all backend options"; exit 1''
    }
    ${
      if observabilityBackend.services.prometheus.enable && observabilityBackend.services.loki.enable && observabilityBackend.services.prometheus.alertmanager.enable
      then ''echo "all backend services enabled by archetype: OK"''
      else ''echo "FAIL: archetype must enable all backend services"; exit 1''
    }

    touch $out
  '';

  inherit centralObservabilityTest;

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
          if !(typeServerConfig.myConfig.prometheus.enable or false)
          then ''echo "  myConfig.prometheus.enable is false on type-server: OK"''
          else ''echo "  FAIL: type-server should not enable myConfig.prometheus"; exit 1''
        }

        ${
          if typeServerConfig.myConfig.nodeExporter.enable
          then ''echo "  myConfig.nodeExporter.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should enable myConfig.nodeExporter"; exit 1''
        }

        ${
          if !(typeServerConfig.myConfig.alertmanager.enable or false)
          then ''echo "  myConfig.alertmanager.enable is false on type-server: OK"''
          else ''echo "  FAIL: type-server should not enable myConfig.alertmanager"; exit 1''
        }

        ${
          if !(typeServerConfig.services.prometheus.enable or false)
          then ''echo "  services.prometheus.enable is false on type-server: OK"''
          else ''echo "  FAIL: type-server should not enable services.prometheus"; exit 1''
        }

        ${
          if typeServerConfig.services.prometheus.exporters.node.enable
          then ''echo "  services.prometheus.exporters.node.enable = true on type-server: OK"''
          else ''echo "  FAIL: type-server should have services.prometheus.exporters.node.enable = true"; exit 1''
        }

        ${
          if !(typeServerConfig.services.prometheus.alertmanager.enable or false)
          then ''echo "  services.prometheus.alertmanager.enable is false on type-server: OK"''
          else ''echo "  FAIL: type-server should not enable services.prometheus.alertmanager"; exit 1''
        }

        # type-server runs no Grafana or local metrics backend. The central
        # observability configuration is selected separately by drlight.
        ${
          if !(typeServerConfig.services.grafana.enable or false)
          then ''echo "  native Grafana service is disabled on type-server: OK"''
          else ''echo "  FAIL: type-server should not run Grafana"; exit 1''
        }

        ${
          if !(typeServerConfig.myConfig.prometheus.openFirewallTailscale or false)
          then ''echo "  Prometheus Tailscale firewall opt-in is false on type-server: OK"''
          else ''echo "  FAIL: type-server should not configure a local Prometheus firewall"; exit 1''
        }

        echo "All type-server observability wiring tests passed"
        touch $out
      '';
}
