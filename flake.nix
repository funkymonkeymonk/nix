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

    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";

    superpowers.url = "github:obra/superpowers";
    superpowers.flake = false;

    opnix.url = "github:brizzbuzz/opnix";
    opnix.inputs.nixpkgs.follows = "nixpkgs";

    devenv.url = "github:cachix/devenv";
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
    microvm,
    ...
  } @ inputs: let
    # Base configuration shared by all systems
    configuration = _: {
      system.configurationRevision = self.rev or self.dirtyRev or null;
      nixpkgs = {
        config = {
          allowUnfree = true;
          allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "claude-code"
            ];
          permittedInsecurePackages = [
            "google-chrome-144.0.7559.97"
          ];
        };
        overlays = [
          (final: _prev: {
            stable = import nixpkgs-stable {
              inherit (final) system config;
            };
          })
          # Use devenv 2.x from the cachix/devenv flake
          (final: _prev: {
            inherit (inputs.devenv.packages.${final.system}) devenv;
          })
          (import ./overlays)
        ];
      };
    };

    # Helper to create user config
    mkUser = name: email: {
      users = [
        {
          inherit name email;
          fullName = "Will Weaver";
          isAdmin = true;
          sshIncludes = [];
        }
      ];
      development.enable = true;
      agent-skills.enable = true;
      onepassword.enable = true;
      jj-autosync = {
        enable = true;
        username = name;
      };
      opencode = {
        enable = true;
        model = "opencode/big-pickle";
      };
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

      # Collect all myConfig options from enabled roles
      roleMyConfigs = map (role: bundles.roles.${role}.config.myConfig or {}) finalRoles;

      # Collect shell aliases from enabled roles
      roleShellAliases =
        nixpkgs.lib.foldl' (
          acc: role:
            acc // (bundles.roles.${role}.config.environment.shellAliases or {})
        ) {}
        finalRoles;

      # Collect session variables from enabled roles
      roleSessionVariables =
        nixpkgs.lib.foldl' (
          acc: role:
            acc // (bundles.roles.${role}.config.environment.sessionVariables or {})
        ) {}
        finalRoles;
    in {
      config =
        {
          # Merge myConfig options from all enabled roles, plus skills config
          myConfig = nixpkgs.lib.mkMerge (
            roleMyConfigs
            ++ [
              {
                skills.enabledRoles = finalRoles;
                skills.superpowersPath = inputs.superpowers;
              }
            ]
          );

          environment =
            {
              systemPackages =
                bundles.roles.base.packages ++ rolePackages ++ bundles.platforms.${system}.packages;

              shellAliases =
                bundles.roles.base.config.environment.shellAliases or {}
                // roleShellAliases;

              # On Darwin, merge session variables into variables since sessionVariables doesn't exist
              # On Linux/NixOS, keep them separate
              variables =
                bundles.roles.base.config.environment.variables or {}
                // bundles.platforms.${system}.config.environment.variables or {}
                // (
                  if system == "darwin"
                  then roleSessionVariables
                  else {}
                );
            }
            // nixpkgs.lib.optionalAttrs (system != "darwin") {
              sessionVariables = roleSessionVariables;
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

    # Darwin-specific modules
    darwinModules = [
      ./modules/darwin/ollama.nix
      ./modules/darwin/litellm.nix
      ./modules/darwin/postgresql.nix
    ];

    # NixOS-specific modules
    nixosModules = [
      ./modules/nixos/ollama.nix
      ./modules/nixos/litellm.nix
      ./modules/nixos/postgresql.nix
    ];

    # Package overlays for each system
    forAllSystems = nixpkgs.lib.genAttrs ["aarch64-darwin" "x86_64-linux"];

    # Helper to create microvm configuration
    mkMicrovm = name: roles:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules =
          [
            microvm.nixosModules.microvm
            home-manager.nixosModules.home-manager
            configuration
          ]
          ++ commonModules
          ++ nixosModules
          ++ [
            ./os/microvm.nix
            ./modules/microvm
            ./targets/microvms/${name}.nix
            (mkBundleModule "linux" roles)
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              myConfig = {
                users = [
                  {
                    name = "dev";
                    email = "dev@localhost";
                    fullName = "Development User";
                    isAdmin = true;
                    sshIncludes = [];
                  }
                ];
                development.enable = true;
                agent-skills.enable = false;
                onepassword.enable = false;
              };
            }
          ];
      };
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [(import ./overlays)];
      };
    in {
      inherit (pkgs) rtk;
    });

    darwinConfigurations = {
      "wweaver" = nix-darwin.lib.darwinSystem {
        modules =
          [
            configuration
            nix-homebrew.darwinModules.nix-homebrew
          ]
          ++ commonModules
          ++ darwinModules
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
                (mkUser "wweaver" "wweaver@justworks.com")
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
                    commands = {
                      diataxis = {
                        description = "Audit and rewrite documentation using the Diataxis framework";
                        template = ''
                          Load the diataxis-docs skill and use it to audit and restructure the documentation in this project.

                          Follow the Diataxis framework to organize content into:
                          - Tutorials (learning-oriented)
                          - How-to guides (goal-oriented)
                          - Reference (information-oriented)
                          - Explanation (understanding-oriented)

                          $ARGUMENTS
                        '';
                      };
                      workspace = {
                        description = "Create a jj workspace for isolated work with fast sync enabled";
                        template = ''
                          Create a new jj workspace for this coding session. This ensures:
                          1. Work is isolated from main branch
                          2. Fast sync (every 5 minutes) is enabled during the session
                          3. Main branch stays clean and synced with upstream

                          Steps to execute:
                          1. First check if we're in a jj repository (look for .jj directory)
                          2. If arguments provided, use them as: jj-workspace-session start <type/topic> [base]
                             - If no type prefix (feat/, fix/, etc.), default to feat/
                             - Example: "/workspace user-auth" creates "feat/user-auth-<date>-<id>"
                             - Example: "/workspace fix/login-bug develop" creates from develop branch
                          3. If no arguments, just start session tracking: jj-workspace-session start
                          4. After workspace is created, cd into it and run jj new to prepare for work
                          5. Report the workspace name and path to the user

                          Arguments: $ARGUMENTS
                        '';
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

      "MegamanX" = nix-darwin.lib.darwinSystem {
        modules =
          [
            mac-app-util.darwinModules.default
            nix-homebrew.darwinModules.nix-homebrew
            configuration
          ]
          ++ commonModules
          ++ darwinModules
          ++ [
            ./modules/home-manager
            ./os/darwin.nix
            ./modules/home-manager/aerospace.nix
            (mkBundleModule "darwin" [
              "developer"
              "desktop"
              "workstation"
              "entertainment"
              "llm-host"
              "llm-server"
              "llm-client"
              "llm-claude"
            ])
            {
              nixpkgs.hostPlatform = "aarch64-darwin";
              system.primaryUser = "monkey";
              system.stateVersion = 4;
              myConfig = mkUser "monkey" "me@willweaver.dev";
              nix-homebrew = mkNixHomebrew "monkey";
            }
            home-manager.darwinModules.home-manager
            {
              home-manager.sharedModules = [opnix.homeManagerModules.default];
            }
          ];
      };

      # Core configuration - minimal bootstrap for any system
      # This provides essential tools (devenv, direnv, git, etc.) for working with this repo
      "core" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          ./modules/common/options.nix
          ./targets/core
          (_: {
            nixpkgs.hostPlatform = "aarch64-darwin";
            system.stateVersion = 4;
            # Core doesn't set primaryUser - it's a minimal bootstrap
            # User-specific settings are disabled to avoid requiring primaryUser
            nix.enable = false;
            # Minimal user config - just enough to bootstrap
            myConfig = {
              users = [];
              development.enable = false;
              agent-skills.enable = false;
              onepassword.enable = false;
              opencode.enable = false;
            };
          })
        ];
      };
    };

    nixosConfigurations = {
      "drlight" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules =
          [
            configuration
          ]
          ++ commonModules
          ++ nixosModules
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
              myConfig = mkUser "monkey" "me@willweaver.dev";
            }
            home-manager.nixosModules.home-manager
            {
              home-manager.sharedModules = [opnix.homeManagerModules.default];
            }
          ];
      };

      "zero" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules =
          [
            configuration
          ]
          ++ commonModules
          ++ nixosModules
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
              myConfig = mkUser "monkey" "me@willweaver.dev";
            }
            home-manager.nixosModules.home-manager
            {
              home-manager.sharedModules = [opnix.homeManagerModules.default];
            }
          ];
      };
    };

    # Note: NixOS core configuration is not provided because it requires
    # hardware-specific filesystem definitions. For NixOS bootstrap:
    # 1. Install NixOS using the standard installer
    # 2. Clone this repo
    # 3. Create a target with your hardware-configuration.nix
    # 4. Apply with: sudo nixos-rebuild switch --flake .#<your-target>

    # Microvm configurations
    microvm.nixosConfigurations = {
      dev-vm = mkMicrovm "dev-vm" ["llm-client"];
    };
  };
}
