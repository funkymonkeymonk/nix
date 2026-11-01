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
        ${checkEqual "type-server target retains admin SSH access" true (server.users.users.admin.openssh.authorizedKeys.keys != [])}
        ${checkEqual "type-server-arm target disables Intel microcode" false serverArm.hardware.cpu.intel.updateMicrocode}
        ${checkEqual "type-server retains single-disk layout" true (server.disko.devices.disk ? main)}
        ${checkEqual "type-server-arm retains single-disk layout" true (serverArm.disko.devices.disk ? main)}

        ${checkEqual "generic headless type-nas does not enable Prometheus" false (nas.services.prometheus.enable or false)}
        ${checkEqual "generic headless type-nas does not enable Loki" false (nas.services.loki.enable or false)}
        ${checkEqual "generic headless type-nas does not enable Alertmanager" false (nas.services.prometheus.alertmanager.enable or false)}
        ${checkEqual "generic headless type-nas enables node_exporter explicitly" true (nas.services.prometheus.exporters.node.enable or false)}
        ${checkEqual "generic headless type-nas does not enable Vector" false (nas.services.vector.enable or false)}
        ${checkEqual "generic headless drlight does not enable Prometheus" false (mediaServer.services.prometheus.enable or false)}
        ${checkEqual "generic headless drlight does not enable Loki" false (mediaServer.services.loki.enable or false)}
        ${checkEqual "generic headless drlight does not enable Alertmanager" false (mediaServer.services.prometheus.alertmanager.enable or false)}

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

        echo "All type-server archetype configuration tests passed"
        touch $out
      '';
in {
  inherit typeServerArchetypeTest;
}
