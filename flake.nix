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
            "olm-3.2.16"
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
            inherit (inputs.devenv.packages.${final.stdenv.hostPlatform.system}) devenv;
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

      # Default LLM endpoint to local Ollama
      # Additional endpoints can be configured via myConfig.llmEndpoints
      defaultLlmHost = "127.0.0.1";
      defaultLlmPort = "11434";

      # Collect all packages from enabled roles
      rolePackages = nixpkgs.lib.concatMap (role: bundles.roles.${role}.packages or []) finalRoles;

      # Collect all homebrew configs from enabled roles
      roleHomebrewConfigs = map (role: bundles.roles.${role}.config.homebrew or {}) finalRoles;

      # Collect all myConfig settings from enabled roles
      roleMyConfigs = map (role: bundles.roles.${role}.config.myConfig or {}) finalRoles;
    in {
      config =
        {
          # Pass enabled roles and superpowers path to skills configuration
          # Merge with myConfig from all enabled roles
          myConfig = nixpkgs.lib.mkMerge (
            roleMyConfigs
            ++ [
              {
                skills.enabledRoles = finalRoles;
                skills.superpowersPath = inputs.superpowers;
              }
              # Configure LLM endpoints when llm-client or llm-claude roles are enabled
              (
                nixpkgs.lib.optionalAttrs
                (builtins.elem "llm-client" enabledRoles || builtins.elem "llm-claude" enabledRoles)
                {
                  llmClient = {
                    serverHost = defaultLlmHost;
                    serverPort = defaultLlmPort;
                  };
                }
              )
            ]
          );

          environment = {
            systemPackages =
              bundles.roles.base.packages ++ rolePackages ++ bundles.platforms.${system}.packages;

            shellAliases =
              bundles.roles.base.config.environment.shellAliases or {}
              // (
                if builtins.elem "llm-client" enabledRoles || builtins.elem "llm-claude" enabledRoles
                then {
                  llm-status = "curl http://${defaultLlmHost}:${defaultLlmPort}/status";
                }
                else {}
              );

            variables =
              bundles.roles.base.config.environment.variables or {}
              // bundles.platforms.${system}.config.environment.variables or {}
              // (
                if builtins.elem "llm-client" enabledRoles || builtins.elem "llm-claude" enabledRoles
                then {
                  LLM_SERVER_HOST = defaultLlmHost;
                  LLM_SERVER_PORT = defaultLlmPort;
                  OPENCODE_ENDPOINT = "http://${defaultLlmHost}:${defaultLlmPort}";
                  CLAUDE_API_BASE = "http://${defaultLlmHost}:${defaultLlmPort}";
                }
                else {}
              );
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
      ./modules/services/ollama/darwin.nix
    ];

    # NixOS-specific modules
    nixosModules = [
      ./modules/services/ollama/nixos.nix
    ];

    # Package overlays for each system
    forAllSystems = nixpkgs.lib.genAttrs [
      "aarch64-darwin"
      "x86_64-linux"
    ];

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

    # Helper to create Darwin host configuration
    mkDarwinHost = {
      target,
      user,
      roles,
      extraModules ? [],
      extraConfig ? {},
    }:
      nix-darwin.lib.darwinSystem {
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
            target
            (mkBundleModule "darwin" roles)
            {
              nixpkgs.hostPlatform = "aarch64-darwin";
              system.stateVersion = 4;
              system.primaryUser = (builtins.head user.users).name;
              myConfig = user // extraConfig;
              nix-homebrew = mkNixHomebrew (builtins.head user.users).name;
            }
            home-manager.darwinModules.home-manager
            {
              home-manager.sharedModules = [opnix.homeManagerModules.default];
            }
          ]
          ++ extraModules;
      };

    # Helper to create NixOS host configuration
    mkNixosHost = {
      target,
      user,
      roles,
      extraModules ? [],
      extraConfig ? {},
    }:
      nixpkgs.lib.nixosSystem {
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
            ./modules/nixos/base.nix
            ./modules/nixos/desktop.nix
            ./modules/nixos/gaming.nix
            ./modules/nixos/streaming.nix
            ./os/nixos.nix
            target
            (mkBundleModule "linux" roles)
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "25.05";
              myConfig = user // extraConfig;
            }
            home-manager.nixosModules.home-manager
            {
              home-manager.sharedModules = [opnix.homeManagerModules.default];
            }
          ]
          ++ extraModules;
      };
  in {
    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import ./overlays)];
        };
      in {
        inherit (pkgs) rtk;
        installer = pkgs.callPackage ./packages/installer {};
      }
    );

    apps = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import ./overlays)];
        };
      in {
        installer = {
          type = "app";
          program = "${pkgs.callPackage ./packages/installer {}}/bin/nixos-flake-installer";
        };
      }
    );

    darwinConfigurations = {
      "wweaver" = mkDarwinHost {
        target = ./targets/wweaver;
        user = mkUser "wweaver" "wweaver@justworks.com";
        roles = [
          "developer"
          "desktop"
          "workstation"
          "llm-host"
          "llm-client"
          "llm-claude"
        ];
        extraConfig = {
          opencode = {
            enable = true;
            disabledProviders = ["opencode"];
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
                  Create a jj workspace session for isolated development work.

                  Run this command:
                  ```bash
                  jj-workspace-session start $ARGUMENTS
                  ```

                  Then report the workspace name and path to the user, and cd into the workspace directory.

                  If no arguments provided, this starts session tracking in the current workspace.
                  If a name is provided (e.g., "feat/auth" or "fix/bug"), it creates a new workspace.
                  A second argument can specify the base branch (defaults to main).

                  Examples:
                  - /workspace feat/user-auth      -> Creates feat/user-auth-<date>-<id> from main
                  - /workspace fix/bug develop     -> Creates fix/bug-<date>-<id> from develop
                  - /workspace                     -> Starts session in current workspace
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
      };

      "MegamanX" = mkDarwinHost {
        target = ./targets/MegamanX;
        user = mkUser "monkey" "me@willweaver.dev";
        roles = [
          "developer"
          "desktop"
          "workstation"
          "entertainment"
          "llm-host"
          "llm-client"
          "llm-claude"
        ];
        extraModules = [mac-app-util.darwinModules.default];
      };

      # Core configuration - minimal bootstrap for any system
      "core" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          ./modules/common/options.nix
          ./targets/core
          (_: {
            nixpkgs.hostPlatform = "aarch64-darwin";
            system.stateVersion = 4;
            nix.enable = false;
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
      # Bootstrap configuration - minimal setup for initial install
      # Used by the installer for all fresh NixOS installations
      "bootstrap" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./targets/bootstrap
          ./modules/common/options.nix
          {
            nixpkgs.hostPlatform = "x86_64-linux";
            system.stateVersion = "25.05";
          }
        ];
      };

      "drlight" = mkNixosHost {
        target = ./targets/drlight;
        user = mkUser "monkey" "me@willweaver.dev";
        roles = ["bootstrap"];
        extraConfig = {
          llmEndpoints = {
            MegamanX = {
              host = "MegamanX.local";
              port = "4000";
            };
          };
        };
      };

      "zero" = mkNixosHost {
        target = ./targets/zero;
        user = mkUser "monkey" "me@willweaver.dev";
        roles = [
          "developer"
          "desktop"
          "llm-client"
        ];
        extraConfig = {
          desktop = {
            enable = true;
            autoLoginUser = "monkey";
          };
          gaming.enable = true;
          streaming.enable = true;
          llmEndpoints = {
            MegamanX = {
              host = "MegamanX.local";
              port = "4000";
            };
          };
        };
      };
    };

    microvm.nixosConfigurations = {
      dev-vm = mkMicrovm "dev-vm" ["llm-client"];
    };
  };
}
