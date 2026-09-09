{
  inputs,
  libraryLib,
  ...
}: {
  flake.nixosConfigurations = {
    # NAS - Network Attached Storage with ZFS and paperless-ngx.
    type-nas = libraryLib.mkNixosSystem {
      inherit inputs;
      hostname = "type-nas";
      modules = [
        ../archetypes/headless-server-nixos.nix
        inputs.disko.nixosModules.disko
        ../../disk-configs/zfs-nas.nix
        ../../targets/hardware-facter.nix
        ../../targets/type-nas
      ];
      overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-nas";
    };

    # Generic foundation-based server configuration.
    type-server = libraryLib.mkNixosSystem {
      inherit inputs;
      hostname = "type-server";
      modules = [
        ../archetypes/headless-server-nixos.nix
        ../../disk-configs/single-disk-ext4.nix
        ../../modules/nixos/vector.nix
        ../../modules/nixos/loki.nix
        ../../modules/nixos/prometheus.nix
        ../../modules/nixos/alertmanager.nix
        ../../targets/hardware-facter.nix
        ../../targets/type-server
      ];
      overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server";
    };

    # ARM64 server variant.
    type-server-arm = libraryLib.mkNixosSystem {
      inherit inputs;
      hostname = "type-server-arm";
      system = "aarch64-linux";
      modules = [
        ../archetypes/headless-server-nixos.nix
        ../../disk-configs/single-disk-ext4.nix
        ../../targets/hardware-facter.nix
        ../../targets/type-server-arm
      ];
      overrides = {
        autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server-arm";
        tailscale.enable = false;
      };
    };

    # Generic desktop configuration.
    type-desktop = libraryLib.mkNixosSystem {
      inherit inputs;
      hostname = "type-desktop";
      modules = [
        ../archetypes/desktop-nixos.nix
        ../../modules/nixos/desktop.nix
        ../../modules/nixos/ghostty-terminfo.nix
        inputs.disko.nixosModules.disko
        ../../disk-configs/single-disk-ext4.nix
        ../../targets/hardware-facter.nix
        ../../targets/type-desktop
      ];
      overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-desktop";
    };
  };
}
