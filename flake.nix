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
    configuration = {lib, ...}: {
      system.configurationRevision = self.rev or self.dirtyRev or null;

      nixpkgs = {
        config.allowUnfree = true;

        # Allow insecure packages for VM testing
        config.permittedInsecurePackages = [
          "lima-1.0.7"
        ];

        # Access unstable pkgs with pkgs.unstable
        overlays = [
          (final: _prev: {
            unstable = import nixpkgs-unstable {
              inherit (final) system config;
            };
          })
        ];
      };
    };

    # Utility function to create VM apps from NixOS configurations
    mkAppVM = name: {
      type = "app";
      program = "${self.nixosConfigurations.${name}.config.system.build.vm}/bin/run-${name}-vm";
    };

    # Utility function to create NixOS configurations with VM support
    mkNixosSystem = modules:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules =
          [
            configuration
            ./modules/common/options.nix
            ./modules/common/users.nix
            ./modules/common/packages.nix
            ./modules/common/shell.nix
            ./modules/home-manager
            ./modules/nixos/hardware.nix
            ./modules/nixos/services.nix
            ./modules/vm # Add VM module for testing
            ./bundles/base
            ./os/nixos.nix
          ]
          ++ modules;
      };
  in {
    darwinConfigurations."wweaver" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/packages.nix
        ./modules/home-manager
        ./bundles/base
        ./bundles/roles/developer
        ./bundles/roles/workstation
        ./bundles/platforms/darwin
        ./os/darwin.nix
        ./modules/home-manager/aerospace.nix
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.primaryUser = "wweaver";
          system.stateVersion = 4;
          # Configure users through the modular system
          myConfig = {
            users = [
              {
                name = "wweaver";
                email = "me@willweaver.dev";
                fullName = "Will Weaver";
                isAdmin = true;
                sshIncludes = [];
              }
            ];
            development.enable = true;
          };
        }
        home-manager.darwinModules.home-manager
      ];
    };

    darwinConfigurations."MegamanX" = nix-darwin.lib.darwinSystem {
      modules = [
        mac-app-util.darwinModules.default
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/packages.nix
        ./modules/home-manager
        ./bundles/base
        ./bundles/roles/developer
        ./bundles/roles/creative
        ./bundles/roles/gaming
        ./bundles/roles/entertainment.nix
        ./bundles/roles/workstation
        ./bundles/platforms/darwin
        ./os/darwin.nix
        ./modules/home-manager/aerospace.nix
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.primaryUser = "monkey";
          system.stateVersion = 4;
          # Configure users through the modular system
          myConfig = {
            users = [
              {
                name = "monkey";
                email = "monkey@willweaver.dev";
                fullName = "Monkey";
                isAdmin = true;
                sshIncludes = ["/Users/monkey/.colima/ssh_config"];
              }
            ];
            development.enable = true;
            media.enable = true;
          };
        }
        home-manager.darwinModules.home-manager
        {
          home-manager.backupFileExtension = "backup";
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

    nixosConfigurations."drlight" = mkNixosSystem [
      ./bundles/roles/developer
      ./bundles/roles/creative
      ./bundles/platforms/linux
      ./targets/drlight
      ./1password.nix
      home-manager.nixosModules.home-manager
      {
        nixpkgs.hostPlatform = "x86_64-linux";
        system.stateVersion = "25.05";
        # Configure users through the modular system
        myConfig = {
          users = [
            {
              name = "monkey";
              email = "monkey@willweaver.dev";
              fullName = "Monkey";
              isAdmin = true;
              sshIncludes = [];
            }
          ];
          development.enable = true;
          media.enable = true;
          vm.enable = true; # Enable VM testing
        };
      }
    ];

    nixosConfigurations."zero" = mkNixosSystem [
      ./bundles/roles/developer
      ./bundles/platforms/linux
      ./targets/zero
      ./1password.nix
      home-manager.nixosModules.home-manager
      {
        nixpkgs.hostPlatform = "x86_64-linux";
        system.stateVersion = "25.05";
        # Configure users through the modular system
        myConfig = {
          users = [
            {
              name = "monkey";
              email = "monkey@willweaver.dev";
              fullName = "Monkey";
              isAdmin = true;
              sshIncludes = [];
            }
          ];
          development.enable = true;
          vm.enable = true; # Enable VM testing
        };
      }
    ];

    # System-specific outputs
    packages.x86_64-linux = {
      # VM outputs for direct access
      vm-drlight = self.nixosConfigurations.drlight.config.system.build.vm;
      vm-zero = self.nixosConfigurations.zero.config.system.build.vm;
    };

    # VM apps for easy testing
    apps.x86_64-linux = {
      # Default VM app (drlight)
      default = mkAppVM "drlight";

      # Individual VM apps
      vm-drlight = mkAppVM "drlight";
      vm-zero = mkAppVM "zero";
    };

    # Development shell with VM tools
    devShells.x86_64-linux.default = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
      pkgs.mkShell {
        buildInputs = with pkgs; [
          qemu
          openssh
          sshpass
        ];

        shellHook = ''
          echo "🔧 NixOS VM Development Environment"
          echo "Available commands:"
          echo "  nix run .#vm-drlight    # Run drlight VM"
          echo "  nix run .#vm-zero       # Run zero VM"
          echo "  task vm:drlight         # Build and run drlight VM"
          echo "  task vm:zero            # Build and run zero VM"
        '';
      };
  };
}
