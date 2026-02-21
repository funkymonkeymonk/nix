{
  description = "Will Weaver system setup flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core.url = "github:homebrew/homebrew-core";
    homebrew-core.flake = false;
    homebrew-cask.url = "github:homebrew/homebrew-cask";
    homebrew-cask.flake = false;

    mac-app-util.url = "github:hraban/mac-app-util";

    superpowers.url = "github:obra/superpowers";
    superpowers.flake = false;

    opnix.url = "github:brizzbuzz/opnix";
    opnix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nix-darwin,
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    mac-app-util,
    nix-homebrew,
    homebrew-core,
    homebrew-cask,
    opnix,
    ...
  } @ inputs: let
    # Base configuration shared by all systems
    configuration = _: {
      system.configurationRevision = self.rev or self.dirtyRev or null;
      nixpkgs.config.allowUnfree = true;
      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (nixpkgs.lib.getName pkg) [
          "claude-code"
        ];
      nixpkgs.overlays = [
        (final: _prev: {
          stable = import nixpkgs-stable {
            inherit (final) system config;
          };
        })
        (import ./overlays)
      ];
    };

    # Helper to create user config
    mkUser = name: {
      users = [
        {
          inherit name;
          email = "me@willweaver.dev";
          fullName = "Will Weaver";
          isAdmin = true;
          sshIncludes = [];
        }
      ];
      development.enable = true;
      agent-skills.enable = true;
      onepassword.enable = true;
      opencode.enable = true;
      claude-code = {
        enable = true;
        rtk.enable = true;
      };
    };

    # Helper for nix-homebrew config
    mkNixHomebrew = user: {
      enable = true;
      enableRosetta = true;
      inherit user;
      taps = {
        "homebrew/homebrew-core" = homebrew-core;
        "homebrew/homebrew-cask" = homebrew-cask;
      };
    };

    # Simplified bundle module - all roles are now flat
    mkBundleModule = system: enabledRoles: {pkgs, ...}: let
      bundles = import ./bundles.nix {inherit pkgs;};

      # Auto-enable agent-skills if any role requests it
      hasAgentSkills =
        builtins.any (
          role: (bundles.roles.${role} or {}).enableAgentSkills or false
        )
        enabledRoles;
      finalRoles =
        if hasAgentSkills
        then nixpkgs.lib.unique (enabledRoles ++ ["agent-skills"])
        else enabledRoles;

      # Collect all packages from enabled roles
      rolePackages = nixpkgs.lib.concatMap (role: bundles.roles.${role}.packages or []) finalRoles;

      # Collect all homebrew configs from enabled roles
      roleHomebrewConfigs = map (role: bundles.roles.${role}.config.homebrew or {}) finalRoles;
    in {
      config =
        {
          # Pass enabled roles to skills configuration
          myConfig.skills.enabledRoles = finalRoles;

          environment = {
            systemPackages =
              bundles.roles.base.packages ++ rolePackages ++ bundles.platforms.${system}.packages;

            shellAliases = bundles.roles.base.config.environment.shellAliases or {};

            variables =
              bundles.roles.base.config.environment.variables or {}
              // bundles.platforms.${system}.config.environment.variables or {};
          };

          programs =
            bundles.roles.base.config.programs or {} // bundles.platforms.${system}.config.programs or {};
        }
        // nixpkgs.lib.optionalAttrs (system == "darwin") {
          homebrew = nixpkgs.lib.mkMerge (
            [
              (bundles.platforms.darwin.config.homebrew or {})
            ]
            ++ roleHomebrewConfigs
          );
        };
    };

    # Common module imports
    commonModules = [
      ./modules/common/options.nix
      ./modules/common/users.nix
      ./modules/common/shell.nix
      ./modules/common/onepassword.nix
      ./modules/common/cachix.nix
    ];

    # Package overlays for each system
    forAllSystems = nixpkgs.lib.genAttrs ["aarch64-darwin" "x86_64-linux"];
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [(import ./overlays)];
      };
    in {
      inherit (pkgs) rtk;
    });
    darwinConfigurations."wweaver" = nix-darwin.lib.darwinSystem {
      modules =
        [
          configuration
          nix-homebrew.darwinModules.nix-homebrew
        ]
        ++ commonModules
        ++ [
          ./modules/home-manager
          ./os/darwin.nix
          ./modules/home-manager/aerospace.nix
          (mkBundleModule "darwin" [
            "developer"
            "desktop"
            "workstation"
            "llm-client"
            "llm-claude"
          ])
          {
            nixpkgs.hostPlatform = "aarch64-darwin";
            system.primaryUser = "wweaver";
            system.stateVersion = 4;
            myConfig =
              (mkUser "wweaver")
              // {
                opencode = {
                  enable = true;
                  disabledProviders = [
                    "opencode"
                  ];
                  extraMcpServers = {
                    github = {
                      type = "remote";
                      url = "https://api.githubcopilot.com/mcp/";
                      enabled = false;
                    };
                    jira = {
                      type = "remote";
                      url = "https://mcp.atlassian.com/v1/mcp";
                      enabled = false;
                    };
                    confluence = {
                      type = "remote";
                      url = "https://mcp.atlassian.com/v1/mcp";
                      enabled = false;
                    };
                  };
                  providers = {
                    just-llms = {
                      npm = "@ai-sdk/openai-compatible";
                      name = "Just LLMs";
                      baseURL = "https://litellm.justworksai.net";
                      onePasswordItem = "op://Justworks/Justworks LiteLLM/wweaver-poweruser-key";
                      models = {
                        "us.anthropic.claude-opus-4-5-20251101-v1:0" = {
                          name = "justworks-dev";
                        };
                      };
                    };
                  };
                };
                claude-code = {
                  enable = true;
                  rtk.enable = true;
                  mcpServers = {
                    github = {
                      type = "remote";
                      url = "https://api.githubcopilot.com/mcp/";
                      enabled = true;
                    };
                    jira = {
                      type = "remote";
                      url = "https://mcp.atlassian.com/v1/mcp";
                      enabled = false;
                    };
                    confluence = {
                      type = "remote";
                      url = "https://mcp.atlassian.com/v1/mcp";
                      enabled = false;
                    };
                  };
                };
              };
            nix-homebrew = mkNixHomebrew "wweaver";
          }
          home-manager.darwinModules.home-manager
          {
            home-manager.sharedModules = [opnix.homeManagerModules.default];
          }
        ];
    };

    darwinConfigurations."MegamanX" = nix-darwin.lib.darwinSystem {
      modules =
        [
          mac-app-util.darwinModules.default
          nix-homebrew.darwinModules.nix-homebrew
          configuration
        ]
        ++ commonModules
        ++ [
          ./os/darwin.nix
          ./modules/home-manager/aerospace.nix
          (mkBundleModule "darwin" [
            "developer"
            "desktop"
            "workstation"
            "entertainment"
            "llm-host"
            "llm-client"
            "llm-claude"
          ])
          {
            nixpkgs.hostPlatform = "aarch64-darwin";
            system.primaryUser = "monkey";
            system.stateVersion = 4;
            myConfig = mkUser "monkey";
            nix-homebrew = mkNixHomebrew "monkey";
          }
          home-manager.darwinModules.home-manager
          {
            home-manager.sharedModules = [opnix.homeManagerModules.default];
          }
        ];
    };

    nixosConfigurations."drlight" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules =
        [
          configuration
        ]
        ++ commonModules
        ++ [
          ./modules/home-manager
          ./os/nixos.nix
          ./targets/drlight
          (mkBundleModule "linux" [
            "developer"
            "creative"
            "llm-client"
          ])
          {
            nixpkgs.hostPlatform = "x86_64-linux";
            system.stateVersion = "25.05";
            myConfig = mkUser "monkey";
          }
          home-manager.nixosModules.home-manager
          {
            home-manager.sharedModules = [opnix.homeManagerModules.default];
          }
        ];
    };

    nixosConfigurations."zero" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules =
        [
          configuration
        ]
        ++ commonModules
        ++ [
          ./modules/home-manager
          ./os/nixos.nix
          ./targets/zero
          (mkBundleModule "linux" [
            "developer"
            "desktop"
            "llm-client"
          ])
          {
            nixpkgs.hostPlatform = "x86_64-linux";
            system.stateVersion = "25.05";
            myConfig = mkUser "monkey";
          }
          home-manager.nixosModules.home-manager
          {
            home-manager.sharedModules = [opnix.homeManagerModules.default];
          }
        ];
    };
  };
}
