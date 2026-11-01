# Evaluated configuration coverage for the reusable type-server archetype.
{
  pkgs,
  self ? null,
  inputs ? {},
  ...
}: let
  inherit (pkgs) lib;
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  typeServer = catalog.type-server;
  typeServerArm = catalog.type-server-arm;
  actualInventory = import ../library/machines/observability-inventory.nix {inherit catalog;};

  hasModule = suffix: machine:
    lib.any (module: lib.hasSuffix suffix (builtins.toString module)) machine.modules;

  checkEqual = name: expected: actual:
    if expected == actual
    then ''echo "${name}: OK"''
    else throw "${name}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";

  typeServerArchetypeTest =
    if self == null
    then
      pkgs.runCommand "test-type-server-archetypes-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else let
      server = self.nixosConfigurations.type-server.config;
      serverArm = self.nixosConfigurations.type-server-arm.config;
      nas = self.nixosConfigurations.type-nas.config;
      mediaServer = self.nixosConfigurations.drlight.config;
      darwinServer = self.darwinConfigurations.darwin-server.config;
      omlxServer = self.darwinConfigurations.MegamanX.config;
      armExporterPort = serverArm.myConfig.nodeExporter.port;
      armFirewallInterfacePorts = lib.concatMap (interface: interface.allowedTCPPorts or []) (builtins.attrValues serverArm.networking.firewall.interfaces);
      actualInventoryNames = map (target: target.name) actualInventory.targets;
    in
      pkgs.runCommand "test-type-server-archetypes" {} ''
        echo "=== Testing evaluated type-server archetype configurations ==="

        ${checkEqual "type-server selects shared archetype" true (hasModule "/archetypes/type-server.nix" typeServer)}
        ${checkEqual "type-server-arm selects shared archetype" true (hasModule "/archetypes/type-server.nix" typeServerArm)}

        ${checkEqual "type-server target module remains present" true (hasModule "/targets/type-server" typeServer)}
        ${checkEqual "type-server-arm target module remains present" true (hasModule "/targets/type-server-arm" typeServerArm)}
        ${checkEqual "type-server disk configuration remains present" true (hasModule "/disk-configs/single-disk-ext4.nix" typeServer)}
        ${checkEqual "type-server-arm disk configuration remains present" true (hasModule "/disk-configs/single-disk-ext4.nix" typeServerArm)}
        ${checkEqual "type-server hardware discovery module remains present" true (hasModule "/targets/hardware-facter.nix" typeServer)}
        ${checkEqual "type-server-arm hardware discovery module remains present" true (hasModule "/targets/hardware-facter.nix" typeServerArm)}

        ${checkEqual "type-server machine identity" "type-server" server.networking.hostName}
        ${checkEqual "type-server-arm machine identity" "type-server-arm" serverArm.networking.hostName}
        ${checkEqual "type-server retains x86_64 platform" "x86_64-linux" server.nixpkgs.hostPlatform.system}
        ${checkEqual "type-server-arm retains aarch64 platform" "aarch64-linux" serverArm.nixpkgs.hostPlatform.system}
        ${checkEqual "type-server retains auto-upgrade URL" "github:funkymonkeymonk/nix#type-server" server.myConfig.autoUpgrade.flakeUrl}
        ${checkEqual "type-server-arm retains auto-upgrade URL" "github:funkymonkeymonk/nix#type-server-arm" serverArm.myConfig.autoUpgrade.flakeUrl}
        ${checkEqual "type-server-arm retains Tailscale override" false serverArm.myConfig.tailscale.enable}
        ${checkEqual "type-server-arm node_exporter remains enabled" true serverArm.services.prometheus.exporters.node.enable}
        ${checkEqual "type-server-arm node_exporter remains in scrape inventory" true (builtins.elem "type-server-arm" actualInventoryNames)}
        ${checkEqual "type-server-arm exporter port is not globally exposed" false (builtins.elem armExporterPort (serverArm.networking.firewall.allowedTCPPorts or []))}
        ${checkEqual "type-server-arm exporter port is not exposed on any interface" false (builtins.elem armExporterPort armFirewallInterfacePorts)}
        ${checkEqual "type-server target retains monkey SSH access" true (server.users.users.monkey.openssh.authorizedKeys.keys != [])}
        ${checkEqual "type-server-arm target disables Intel microcode" false serverArm.hardware.cpu.intel.updateMicrocode}
        ${checkEqual "type-server retains single-disk layout" true (server.disko.devices.disk ? main)}
        ${checkEqual "type-server-arm retains single-disk layout" true (serverArm.disko.devices.disk ? main)}

        ${checkEqual "generic headless type-nas does not enable Prometheus" false (nas.services.prometheus.enable or false)}
        ${checkEqual "generic headless type-nas does not enable Loki" false (nas.services.loki.enable or false)}
        ${checkEqual "generic headless type-nas does not enable Alertmanager" false (nas.services.prometheus.alertmanager.enable or false)}
        ${checkEqual "generic headless type-nas enables node_exporter explicitly" true (nas.services.prometheus.exporters.node.enable or false)}
        ${checkEqual "generic headless type-nas does not enable Vector" false (nas.services.vector.enable or false)}
        ${checkEqual "drlight enables central Prometheus" true (mediaServer.services.prometheus.enable or false)}
        ${checkEqual "drlight enables central Loki receiver" true (mediaServer.services.loki.enable or false)}
        ${checkEqual "drlight enables central Alertmanager" true (mediaServer.services.prometheus.alertmanager.enable or false)}

        ${checkEqual "type-server does not enable Prometheus" false (server.services.prometheus.enable or false)}
        ${checkEqual "type-server does not enable Loki" false (server.services.loki.enable or false)}
        ${checkEqual "type-server does not enable Alertmanager" false (server.services.prometheus.alertmanager.enable or false)}
        ${checkEqual "type-server-arm does not enable Prometheus" false (serverArm.services.prometheus.enable or false)}
        ${checkEqual "type-server-arm does not enable Loki" false (serverArm.services.loki.enable or false)}
        ${checkEqual "type-server-arm does not enable Alertmanager" false (serverArm.services.prometheus.alertmanager.enable or false)}

        ${checkEqual "type-server enables Vector" true (server.services.vector.enable or false)}
        ${checkEqual "type-server-arm enables Vector" true (serverArm.services.vector.enable or false)}
        ${checkEqual "type-server enables node_exporter" true (server.services.prometheus.exporters.node.enable or false)}
        ${checkEqual "type-server-arm enables node_exporter" true (serverArm.services.prometheus.exporters.node.enable or false)}

        ${checkEqual "type-server collector destination is drlight" "drlight" server.myConfig.collector.destinationHostname}
        ${checkEqual "type-server-arm collector destination is drlight" "drlight" serverArm.myConfig.collector.destinationHostname}
        ${checkEqual "drlight collector destination retains localhost" "localhost" mediaServer.myConfig.collector.destinationHostname}

        ${checkEqual "Darwin server has no Prometheus backend" false (darwinServer.services.prometheus.enable or false)}
        ${checkEqual "Darwin server has no Alertmanager backend" false (darwinServer.services.prometheus.alertmanager.enable or false)}
        ${checkEqual "Darwin server has no Loki backend" false (darwinServer.services.loki.enable or false)}
        ${checkEqual "Darwin server has no Grafana backend" false (darwinServer.myConfig.grafana.enable or false)}
        ${checkEqual "Darwin server retains Vector collector" true darwinServer.myConfig.vector.enable}
        ${checkEqual "Darwin server Vector routes to drlight" "drlight" darwinServer.myConfig.collector.destinationHostname}

        ${checkEqual "Darwin server retains catalog node_exporter" true darwinServer.myConfig.nodeExporter.enable}
        ${checkEqual "Darwin server exporter remains loopback-only" "127.0.0.1:9100" darwinServer.myConfig.nodeExporter.listenAddress}
        ${checkEqual "Darwin server exporter remains in scrape inventory" true (builtins.elem "darwin-server" actualInventoryNames)}
        ${checkEqual "oMLX Darwin has no Prometheus backend" false (omlxServer.myConfig.prometheus.enable or false)}
        ${checkEqual "oMLX Darwin has no Prometheus service" false (omlxServer.launchd.daemons ? prometheus)}
        ${checkEqual "oMLX Darwin retains catalog node_exporter" true omlxServer.myConfig.nodeExporter.enable}
        ${checkEqual "oMLX Darwin exporter remains loopback-only" "127.0.0.1:9100" omlxServer.myConfig.nodeExporter.listenAddress}
        ${checkEqual "oMLX Darwin exporter remains in scrape inventory" true (builtins.elem "MegamanX" actualInventoryNames)}
        ${checkEqual "oMLX Darwin does not gain Vector" false (omlxServer.myConfig.vector.enable or false)}

        echo "All type-server archetype configuration tests passed"
        touch $out
      '';
in {
  inherit typeServerArchetypeTest;
}
