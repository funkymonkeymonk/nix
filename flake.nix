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
    inherit (nixpkgs) lib;

    configuration = {lib, ...}: {
      system.configurationRevision = self.rev or self.dirtyRev or null;

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

    # Helper function to create bundle module from our consolidated bundles.nix
    mkBundleModule = system: enabledRoles: {
      pkgs,
      lib,
      ...
    }: {
      config = let
        bundles = import ./bundles.nix {inherit pkgs lib;};

        baseConfig = {
          environment = {
            systemPackages =
              bundles.roles.base.packages
              ++ lib.concatMap (role: bundles.roles.${role}.packages or []) enabledRoles
              ++ bundles.platforms.${system}.packages;

            # Merge shell aliases from base bundle
            shellAliases = bundles.roles.base.config.environment.shellAliases or {};

            # Additional system configuration from bundles
            variables =
              bundles.roles.base.config.environment.variables or {}
              // bundles.platforms.${system}.config.environment.variables or {};
          };

          # Merge configurations from all enabled bundles
          programs =
            bundles.roles.base.config.programs or {}
            // bundles.platforms.${system}.config.programs or {};
        };

        # Platform-specific configurations
        darwinConfig = lib.optionalAttrs (system == "darwin") {
          homebrew =
            bundles.platforms.darwin.config.homebrew or {}
            // lib.mkMerge (map (role: bundles.roles.${role}.config.homebrew or {}) enabledRoles);
        };
      in
        baseConfig // darwinConfig;
    };
  in {
    darwinConfigurations."wweaver" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/home-manager
        ./os/darwin.nix
        ./modules/home-manager/aerospace.nix
        (mkBundleModule "darwin" ["developer" "workstation"])
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
        ./modules/home-manager
        ./os/darwin.nix
        ./modules/home-manager/aerospace.nix
        (mkBundleModule "darwin" ["developer" "creative" "gaming" "entertainment" "workstation"])
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
          # Additional homebrew casks specific to MegamanX
          homebrew.casks = [
            "autodesk-fusion"
            "xtool-studio"
            "orcaslicer"
            "openscad"
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
        ./modules/common/shell.nix
        ./modules/home-manager
        ./modules/nixos/hardware.nix
        ./modules/nixos/services.nix
        ./os/nixos.nix
        ./targets/drlight
        (mkBundleModule "linux" ["developer" "creative"])
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
          };
        }
        ./1password.nix
        home-manager.nixosModules.home-manager
      ];
    };

    nixosConfigurations."zero" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/shell.nix
        ./modules/home-manager
        ./modules/nixos/hardware.nix
        ./os/nixos.nix
        ./targets/zero
        (mkBundleModule "linux" ["developer"])
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
          };
        }
        ./1password.nix
        home-manager.nixosModules.home-manager
      ];
    };
  };
}
