{
  pkgs,
  inputs,
  ...
}: let
  lib = pkgs.lib;
  catalog = {
    nixos-default = {
      kind = "nixos";
      hostname = "metrics-a.example";
      nodeExporter.enable = true;
    };
    nixos-disabled = {
      kind = "nixos";
      hostname = "metrics-disabled.example";
      nodeExporter.enable = false;
    };
    nixos-override = {
      kind = "nixos";
      hostname = "ignored.example";
      nodeExporter = {
        enable = true;
        address = "192.0.2.18";
        port = 9200;
      };
    };
    darwin-custom-port = {
      kind = "darwin";
      hostname = "mac.example";
      nodeExporter = {
        enable = true;
        port = 9102;
      };
    };
    nixos-ipv6 = {
      kind = "nixos";
      hostname = "ipv6.example";
      nodeExporter = {
        enable = true;
        address = "2001:db8::18";
      };
    };
  };
  inventory = import ../library/machines/observability-inventory.nix {inherit catalog;};
  targets = inventory.targets;
  actualCatalog = import ../library/machines/catalog.nix {inherit inputs;};
  actualInventory = import ../library/machines/observability-inventory.nix {catalog = actualCatalog;};
  stubs = import ./stubs.nix {inherit pkgs;};
  prometheusConfig =
    (lib.evalModules {
      specialArgs.nodeExporterInventory = targets;
      modules =
        stubs.base
        ++ stubs.nixosService
        ++ [
          ../modules/nixos/prometheus.nix
          {config.myConfig.prometheus.enable = true;}
        ];
    }).config;
  nodeScrapeTargets = let
    nodeScrape = builtins.head (builtins.filter (scrape: scrape.job_name == "node") prometheusConfig.services.prometheus.scrapeConfigs);
  in
    (builtins.head nodeScrape.static_configs).targets;
  prometheusSelfScrapeTargets = let
    selfScrape = builtins.head (builtins.filter (scrape: scrape.job_name == "prometheus") prometheusConfig.services.prometheus.scrapeConfigs);
  in
    (builtins.head selfScrape.static_configs).targets;
  drlightTarget = builtins.head (builtins.filter (target: target.name == "drlight") actualInventory.targets);
  projected = lib.evalModules {
    modules = [
      ({lib, ...}: {
        options.projectedInventory = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [];
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
      })
      (inventory.machineModule catalog.nixos-override)
      ({nodeExporterInventory, ...}: {config.projectedInventory = nodeExporterInventory;})
    ];
  };
  assertEqual = name: expected: actual:
    if expected == actual
    then ''echo "${name}: OK"''
    else throw "${name}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";
  enabledTargetNames = map (target: target.name) targets;
  enabledAddresses = map (target: target.target) targets;
  actualMachineNames = builtins.filter (name: builtins.elem actualCatalog.${name}.kind ["nixos" "darwin"]) (builtins.attrNames actualCatalog);
  actualMachineExporterStates =
    map (name: let
      machine = actualCatalog.${name};
      effective =
        (lib.evalModules {
          modules = [
            ({lib, ...}: {
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
            })
            (actualInventory.machineModule machine)
            {config.myConfig.nodeExporter.enable = true;}
          ];
        }).config.myConfig.nodeExporter.enable;
    in {
      inherit name effective;
      expected = (machine.nodeExporter or {}).enable or false;
    })
    actualMachineNames;
  expectedMachineExporterStates = map (state: state.expected) actualMachineExporterStates;
  effectiveMachineExporterStates = map (state: state.effective) actualMachineExporterStates;
  test = pkgs.runCommand "test-observability-inventory" {} ''
    echo "=== Testing catalog-derived node-exporter inventory ==="
    ${assertEqual "enabled records included once" 4 (builtins.length targets)}
    ${assertEqual "enabled record names" ["darwin-custom-port" "nixos-default" "nixos-ipv6" "nixos-override"] enabledTargetNames}
    ${assertEqual "disabled records omitted" false (builtins.elem "nixos-disabled" enabledTargetNames)}
    ${assertEqual "default address uses hostname and default port" "metrics-a.example:9100" (builtins.elemAt enabledAddresses 1)}
    ${assertEqual "explicit address and port preserved" "192.0.2.18:9200" (builtins.elemAt enabledAddresses 3)}
    ${assertEqual "Darwin port preserved" "mac.example:9102" (builtins.elemAt enabledAddresses 0)}
    ${assertEqual "NixOS and Darwin records are both represented" ["darwin" "nixos" "nixos" "nixos"] (map (target: target.kind) targets)}
    ${assertEqual "projected exporter enablement follows catalog" true projected.config.myConfig.nodeExporter.enable}
    ${assertEqual "projected exporter port follows catalog" 9200 projected.config.myConfig.nodeExporter.port}
    ${assertEqual "inventory is available to machine modules" targets projected.config.projectedInventory}
    ${assertEqual "Prometheus scrapes exactly the generated inventory" enabledAddresses nodeScrapeTargets}
    ${assertEqual "Prometheus keeps its self-scrape in addition to inventory" ["localhost:9090"] prometheusSelfScrapeTargets}
    ${assertEqual "drlight remains a catalog target at its default hostname and port" "drlight:9100" drlightTarget.target}
    ${assertEqual "real catalog exporter enablement is authoritative for every machine" expectedMachineExporterStates effectiveMachineExporterStates}
    ${assertEqual "IPv6 address is bracketed in Prometheus target" "[2001:db8::18]:9100" (builtins.elemAt enabledAddresses 2)}
    ${assertEqual "real catalog exporters included once" ["MegamanX" "darwin-server" "drlight" "type-nas" "type-server" "type-server-arm"] (map (target: target.name) actualInventory.targets)}
    ${assertEqual "real catalog contains both NixOS and Darwin exporters" ["darwin" "darwin" "nixos" "nixos" "nixos" "nixos"] (map (target: target.kind) actualInventory.targets)}
    echo "All catalog-derived node-exporter inventory tests passed"
    touch $out
  '';
in {
  observabilityInventory = test;
}
