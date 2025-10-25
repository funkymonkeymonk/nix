{
  description = "Will Weaver system setup flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core.url = "github:homebrew/homebrew-core";
    homebrew-core.flake = false;
    homebrew-cask.url = "github:homebrew/homebrew-cask";
    homebrew-cask.flake = false;

    mac-app-util.url = "github:hraban/mac-app-util";
  };

  outputs = {
    self,
    nix-darwin,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    mac-app-util,
    ...
  }: let
    configuration = _: {
      system.configurationRevision = self.rev or self.dirtyRev or null;
      system.stateVersion = "25.05";

      nixpkgs.config.allowUnfree = true;

      # Access unstable pkgs with pkgs.unstable
      nixpkgs.overlays = [
        (final: _prev: {
          unstable = import nixpkgs-unstable {
            inherit (final) system config;
          };
        })
      ];
    };
  in {
    darwinConfigurations."Will-Stride-MBP" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/packages.nix
        ./modules/common/macos.nix
        ./bundles/base
        ./bundles/roles/developer
        ./bundles/roles/workstation
        ./bundles/platforms/darwin
        ./modules/homebrew
        ./modules/home-manager/desktop.nix
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.primaryUser = "willweaver";
          # Configure users through the modular system
          myConfig = {
            users = [
              {
                name = "monkey";
                email = "monkey@willweaver.dev";
                fullName = "Monkey";
                isAdmin = true;
              }
            ];
            development.enable = true;
            media.enable = true;
            macos.enable = true;
          };
        }
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.willweaver = import ./home.nix;
          };
        }
      ];
    };

    darwinConfigurations."MegamanX" = nix-darwin.lib.darwinSystem {
      modules = [
        mac-app-util.darwinModules.default
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/packages.nix
        ./modules/common/macos.nix
        ./bundles/base
        ./bundles/roles/developer
        ./bundles/roles/creative
        ./bundles/roles/gaming
        ./bundles/roles/workstation
        ./bundles/platforms/darwin
        ./modules/homebrew
        ./modules/home-manager/desktop.nix
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.primaryUser = "monkey";
          # Configure users through the modular system
          myConfig = {
            users = [
              {
                name = "monkey";
                email = "monkey@willweaver.dev";
                fullName = "Monkey";
                isAdmin = true;
              }
            ];
            development.enable = true;
            media.enable = true;
          };
        }
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.monkey = import ./home.nix;
          };
        }
        {
          homebrew.casks = [
            "autodesk-fusion"
            "deezer"
            "discord"
            "xtool-studio"
            "orcaslicer"
            "openscad"
            "ollama-app"
            "block-goose"
            "obs"
            "pocket-casts"
            "steam"
            "sensei"
          ];
        }
      ];
    };

    nixosConfigurations."drlight" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/packages.nix
        ./modules/nixos/hardware.nix
        ./modules/nixos/services.nix
        ./bundles/base
        ./bundles/roles/developer
        ./bundles/roles/creative
        ./bundles/platforms/linux
        ./os/nixos.nix
        ./targets/drlight
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          # Configure users through the modular system
          myConfig = {
            users = [
              {
                name = "monkey";
                email = "monkey@willweaver.dev";
                fullName = "Monkey";
                isAdmin = true;
              }
            ];
            development.enable = true;
            media.enable = true;
          };
        }
        ./1password.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
      ];
    };

    nixosConfigurations."zero" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/packages.nix
        ./modules/nixos/hardware.nix
        ./bundles/base
        ./bundles/roles/developer
        ./bundles/platforms/linux
        ./os/nixos.nix
        ./targets/zero
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          # Configure users through the modular system
          myConfig = {
            users = [
              {
                name = "monkey";
                email = "monkey@willweaver.dev";
                fullName = "Monkey";
                isAdmin = true;
              }
            ];
            development.enable = true;
          };
        }
        ./1password.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
      ];
    };
  };
}
