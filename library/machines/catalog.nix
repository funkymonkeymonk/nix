{inputs}: {
  bootstrap = {
    kind = "nixos";
    secretProfile = "Personal";
    builder = "nixos";
    system = "x86_64-linux";
    hostname = null;
    modules = [
      ../../modules/common/core.nix
      ../../targets/bootstrap
      ../../modules/common/options.nix
    ];
    extraSpecialArgs = {};
    overrides = {};
  };

  type-nas = {
    kind = "nixos";
    secretProfile = "Homelab";
    disko = true;
    builder = "mk-system";
    system = "x86_64-linux";
    hostname = "type-nas";
    nodeExporter.enable = true;
    modules = [
      ../archetypes/headless-server-nixos.nix
      ../../disk-configs/zfs-nas.nix
      ../../targets/hardware-facter.nix
      ../../targets/type-nas
    ];
    extraSpecialArgs = {};
    overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-nas";
  };

  type-server = {
    kind = "nixos";
    secretProfile = "Homelab";
    builder = "mk-system";
    system = "x86_64-linux";
    hostname = "type-server";
    nodeExporter.enable = true;
    modules = [
      ../archetypes/type-server.nix
      ../../disk-configs/single-disk-ext4.nix
      ../../targets/hardware-facter.nix
      ../../targets/type-server
    ];
    extraSpecialArgs = {};
    overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server";
  };

  type-server-arm = {
    kind = "nixos";
    secretProfile = "Homelab";
    builder = "mk-system";
    system = "aarch64-linux";
    hostname = "type-server-arm";
    nodeExporter.enable = true;
    modules = [
      ../archetypes/type-server.nix
      ../../disk-configs/single-disk-ext4.nix
      ../../targets/hardware-facter.nix
      ../../targets/type-server-arm
    ];
    extraSpecialArgs = {};
    overrides = {
      autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server-arm";
      tailscale.enable = false;
    };
  };

  type-desktop = {
    kind = "nixos";
    secretProfile = "Personal";
    disko = true;
    builder = "mk-system";
    system = "x86_64-linux";
    hostname = "type-desktop";
    modules = [
      ../archetypes/desktop-nixos.nix
      ../../modules/nixos/desktop.nix
      ../../modules/nixos/ghostty-terminfo.nix
      ../../disk-configs/single-disk-ext4.nix
      ../../targets/hardware-facter.nix
      ../../targets/type-desktop
    ];
    extraSpecialArgs = {};
    overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-desktop";
  };

  installer-iso = {
    kind = "nixos";
    secretProfile = "Personal";
    builder = "nixos";
    system = "x86_64-linux";
    hostname = null;
    modules = [
      ../../targets/installer-iso/default.nix
    ];
    extraSpecialArgs = {inherit inputs;};
    overrides = {};
  };

  zero = {
    kind = "nixos";
    secretProfile = "Homelab";
    disko = true;
    builder = "mk-system";
    system = "x86_64-linux";
    hostname = "zero";
    modules = [
      ../archetypes/desktop-nixos.nix
      ../../modules/nixos/base.nix
      ../../modules/nixos/desktop.nix
      ../../modules/nixos/gaming.nix
      ../../modules/nixos/streaming.nix
      ../../modules/services/caddy/nixos.nix
      ../../os/nixos.nix
      ../../disk-configs/zero.nix
      ../archetypes/desktop-machine.nix
      ../../modules/nixos/ghostty-terminfo.nix
      ../../targets/zero
    ];
    extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
    overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#zero";
  };

  drlight = {
    kind = "nixos";
    secretProfile = "Homelab";
    builder = "mk-system";
    system = "x86_64-linux";
    hostname = "drlight";
    nodeExporter.enable = true;
    modules = [
      ../archetypes/type-media-center.nix
      ../archetypes/type-observability.nix
      ../../modules/nixos/media-storage.nix
      ../../modules/nixos/ghostty-terminfo.nix
      ../../targets/drlight
    ];
    extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
    overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#drlight";
  };

  wweaver = {
    kind = "darwin";
    secretProfile = "Personal";
    builder = "mk-system";
    system = "aarch64-darwin";
    hostname = "wweaver";
    modules = [
      ../../modules/services/bifrost/darwin.nix
      ../../modules/services/omlx/darwin.nix
      ../../modules/home-manager/aerospace.nix
      ../../hosts/wweaver
    ];
    extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
    overrides = {};
  };

  darwin-server = {
    kind = "darwin";
    secretProfile = "Personal";
    builder = "mk-system";
    system = "aarch64-darwin";
    hostname = "darwin-server";
    nodeExporter.enable = true;
    modules = [
      ../archetypes/headless-server-darwin.nix
      {
        nixpkgs.config.permittedInsecurePackages = [
          "olm-3.2.16"
        ];
      }
      ../../hosts/darwin-server
    ];
    extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
    overrides = {};
  };

  MegamanX = {
    kind = "darwin";
    secretProfile = "MegamanX";
    builder = "mk-system";
    system = "aarch64-darwin";
    hostname = "MegamanX";
    nodeExporter.enable = true;
    modules = [
      ../../modules/services/bifrost/darwin.nix
      ../../modules/services/searxng/darwin.nix
      ../../modules/services/caddy/darwin.nix
      ../../modules/services/omlx/darwin.nix
      ../../modules/services/temporal/darwin.nix
      ../../hosts/megamanx
    ];
    extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
    overrides = {};
  };
}
