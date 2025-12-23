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
    nix-homebrew,
    homebrew-core,
    homebrew-cask,
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

        # Helper to collect packages from nested bundle structure
        collectPackages = path: default: let
          parts = lib.splitString "." path;
        in
          if lib.hasAttrByPath parts bundles
          then (lib.attrsets.getAttrFromPath parts bundles).packages or []
          else default;

        # Helper to collect config from nested bundle structure
        collectConfig = path: default: let
          parts = lib.splitString "." path;
        in
          if lib.hasAttrByPath parts bundles
          then (lib.attrsets.getAttrFromPath parts bundles).config or {}
          else default;

        baseConfig = {
          environment = {
            systemPackages =
              bundles.roles.base.packages
              ++ lib.concatMap (role: bundles.roles.${role}.packages or []) enabledRoles
              ++ bundles.platforms.${system}.packages
              # Add llms packages based on enabled roles
              ++ (lib.optionals (lib.elem "wweaver_llm_client" enabledRoles) (collectPackages "roles.llms.client.opensource" []))
              ++ (lib.optionals (lib.elem "wweaver_claude_client" enabledRoles) (collectPackages "roles.llms.client.claude" []))
              ++ (lib.optionals (lib.elem "megamanx_llm_host" enabledRoles) (collectPackages "roles.llms.host" []))
              ++ (lib.optionals (lib.elem "megamanx_llm_server" enabledRoles) (collectPackages "roles.llms.server" []));

            # Merge shell aliases from base bundle
            shellAliases =
              bundles.roles.base.config.environment.shellAliases or {};

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
          homebrew = let
            roleHomebrewConfigs = map (role: bundles.roles.${role}.config.homebrew or {}) enabledRoles;
            llmHostHomebrewConfig =
              if lib.elem "megamanx_llm_host" enabledRoles
              then (collectConfig "roles.llms.host" {}).homebrew or {}
              else {};
          in
            lib.mkMerge ([
                (bundles.platforms.darwin.config.homebrew or {})
              ]
              ++ roleHomebrewConfigs
              ++ [
                llmHostHomebrewConfig
              ]);
        };
      in
        baseConfig // darwinConfig;
    };
  in {
    darwinConfigurations."wweaver" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        nix-homebrew.darwinModules.nix-homebrew
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/home-manager
        ./os/darwin.nix
        ./modules/home-manager/aerospace.nix
        (mkBundleModule "darwin" ["developer" "workstation" "wweaver_llm_client" "wweaver_claude_client"])
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

          # Configure nix-homebrew
          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            user = "wweaver";
            taps = {
              "homebrew/homebrew-core" = homebrew-core;
              "homebrew/homebrew-cask" = homebrew-cask;
            };
          };
        }
        home-manager.darwinModules.home-manager
      ];
    };

    darwinConfigurations."MegamanX" = nix-darwin.lib.darwinSystem {
      modules = [
        mac-app-util.darwinModules.default
        nix-homebrew.darwinModules.nix-homebrew
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/home-manager
        ./os/darwin.nix
        ./modules/home-manager/aerospace.nix
        (mkBundleModule "darwin" ["developer" "creative" "gaming" "entertainment" "workstation" "wweaver_llm_client" "megamanx_llm_host" "megamanx_llm_server"])
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

          # Configure nix-homebrew
          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            autoMigrate = true;
            user = "monkey";
            taps = {
              "homebrew/homebrew-core" = homebrew-core;
              "homebrew/homebrew-cask" = homebrew-cask;
            };
          };
        }
        home-manager.darwinModules.home-manager
        {
          home-manager.backupFileExtension = "backup";
          # Add ollama launchd agent for MegamanX
          home-manager.users.monkey.launchd.agents.ollama = {
            enable = true;
            config = {
              ProgramArguments = ["ollama" "serve"];
              RunAtLoad = true;
              KeepAlive = {
                SuccessfulExit = false;
                NetworkState = true;
                PathState = {
                  "/Users/monkey/.ollama/models" = true;
                };
              };
              StandardOutPath = "/tmp/ollama-launchd.log";
              StandardErrorPath = "/tmp/ollama-launchd.err";
              EnvironmentVariables = {
                OLLAMA_HOST = "127.0.0.1";
                OLLAMA_PORT = "11434";
                OLLAMA_MODELS = "/Users/monkey/.ollama/models";
                OLLAMA_DEBUG = "INFO";
              };
              # Add delay to prevent rapid restarts
              ThrottleInterval = 10;
            };
          };
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
        (mkBundleModule "linux" ["developer" "creative" "wweaver_llm_client"])
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
        (mkBundleModule "linux" ["developer" "wweaver_llm_client"])
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
