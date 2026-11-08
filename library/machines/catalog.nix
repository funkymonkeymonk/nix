{inputs}: let
  mkCatalogMachine = import ./mk-catalog-machine.nix;
  nixosMachine = mkCatalogMachine {kind = "nixos";};
  darwinMachine = mkCatalogMachine {
    kind = "darwin";
    extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
  };
in {
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

  type-nas = nixosMachine {
    secretProfile = "Opnix";
    disko = true;
    system = "x86_64-linux";
    hostname = "type-nas";
    nodeExporter.enable = true;
    modules = [
      ../archetypes/headless-server-nixos.nix
      ../../disk-configs/zfs-nas.nix
      ../../targets/hardware-facter.nix
      ../../machines/type-nas
    ];
    overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-nas";
  };

  type-server = nixosMachine {
    secretProfile = "Opnix";
    disko = true;
    system = "x86_64-linux";
    hostname = "type-server";
    nodeExporter.enable = true;
    modules = [
      ../archetypes/type-server.nix
      ../../disk-configs/single-disk-ext4.nix
      ../../targets/hardware-facter.nix
    ];
    overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server";
  };

  type-server-arm = nixosMachine {
    secretProfile = "Opnix";
    disko = true;
    system = "aarch64-linux";
    hostname = "type-server-arm";
    nodeExporter.enable = true;
    modules = [
      ../archetypes/type-server.nix
      ../../disk-configs/single-disk-ext4.nix
      ../../targets/hardware-facter.nix
      ../../machines/type-server-arm
    ];
    overrides = {
      autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server-arm";
      tailscale.enable = false;
    };
  };

  type-desktop = nixosMachine {
    secretProfile = "Personal";
    disko = true;
    system = "x86_64-linux";
    hostname = "type-desktop";
    modules = [
      ../archetypes/desktop-nixos.nix
      ../../modules/nixos/desktop.nix
      ../../modules/nixos/ghostty-terminfo.nix
      ../../disk-configs/single-disk-ext4.nix
      ../../targets/hardware-facter.nix
      ../../machines/type-desktop
    ];
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

  zero = nixosMachine {
    secretProfile = "Opnix";
    disko = true;
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
      ../../machines/zero
    ];
    extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
    overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#zero";
  };

  drlight = nixosMachine {
    secretProfile = "Opnix";
    disko = true;
    system = "x86_64-linux";
    hostname = "drlight";
    nodeExporter.enable = true;
    modules = [
      ../archetypes/type-media-center.nix
      ../archetypes/type-observability.nix
      ../../disk-configs/drlight.nix
      ../../modules/nixos/media-storage.nix
      ../../modules/nixos/ultra-media-sync.nix
      ../../modules/nixos/tailscale-home-dns.nix
      ../../modules/nixos/ghostty-terminfo.nix
      ../../machines/drlight
    ];
    extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
    install.secrets."/etc/opnix/token" = {
      secret = "OPNIX_SERVICE_ACCOUNT_TOKEN";
      owner = "0:0";
      mode = "0600";
    };
    overrides = {
      autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#drlight";
      tailscale.authKeyMode = "devenv-oauth";
      tailscale.authKeyTags = ["tag:home-lab" "tag:media-center"];
    };
  };

  wweaver = darwinMachine {
    secretProfile = "Personal";
    system = "aarch64-darwin";
    hostname = "wweaver";
    modules = [
      ../../modules/services/bifrost/darwin.nix
      ../../modules/services/omlx/darwin.nix
      ../../modules/home-manager/aerospace.nix
      ../../machines/wweaver
    ];
  };

  darwin-server = darwinMachine {
    secretProfile = "Personal";
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
      ../../machines/darwin-server
    ];
  };

  MegamanX = darwinMachine {
    secretProfile = "MegamanX";
    system = "aarch64-darwin";
    hostname = "MegamanX";
    nodeExporter.enable = true;
    modules = [
      ../../modules/services/bifrost/darwin.nix
      ../../modules/services/searxng/darwin.nix
      ../../modules/services/caddy/darwin.nix
      ../../modules/services/omlx/darwin.nix
      ../../modules/services/temporal/darwin.nix
      ../../machines/megamanx
    ];
  };
}
