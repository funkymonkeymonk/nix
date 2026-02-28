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

    nix-openclaw.url = "github:openclaw/nix-openclaw";
    nix-openclaw.inputs.nixpkgs.follows = "nixpkgs";

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
    nix-openclaw,
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
    in {
      config =
        {
          # Pass enabled roles and superpowers path to skills configuration
          myConfig.skills.enabledRoles = finalRoles;
          myConfig.skills.superpowersPath = inputs.superpowers;

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

    # Helper to create SECURE OpenClaw microvm configuration with GitHub integration
    # Uses GitHub PRs for all changes - no direct filesystem modification
    mkOpenclawMicrovm = { name, targetRepo }:  # targetRepo = "funkymonkeymonk/nix"
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules =
          [
            microvm.nixosModules.microvm
            home-manager.nixosModules.home-manager
            nix-openclaw.homeManagerModules.default
            configuration
          ]
          ++ commonModules
          ++ [
            ./os/microvm.nix
            ./targets/microvms/${name}.nix
            ({ config, pkgs, ... }: {
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "25.05";
              
              # Install required packages + PAT request script
              environment.systemPackages = with pkgs; [
                git
                gh
                jq
                vim
                curl
                (writeShellScriptBin "openclaw-request-pat" 
                  (builtins.readFile ./scripts/openclaw-request-pat.sh))
              ];
              
              # Security hardening for OpenClaw
              security.sudo.wheelNeedsPassword = true;
              
              # Create openclaw user
              users.users.openclaw = {
                isNormalUser = true;
                description = "OpenClaw AI Agent";
                extraGroups = [];
                shell = pkgs.bash;
                home = "/home/openclaw";
                openssh.authorizedKeys.keys = [];
              };
              
              # Enable 1Password CLI for secret access
              programs._1password.enable = true;
              
              # OpenClaw Home Manager configuration with opnix secrets
              home-manager.users.openclaw = { ... }: {
                programs.openclaw = {
                  enable = true;
                  config = {
                    gateway = {
                      mode = "local";
                      auth = {
                        token = "{file:/run/secrets/gateway-token}";
                      };
                    };
                    # Nix mode - disables auto-install/self-mutation
                    nixMode = true;
                    # Configure the workspace as the target repo
                    workspace = {
                      path = "/home/openclaw/nix";
                      repo = "https://github.com/${targetRepo}.git";
                    };
                    # Git configuration with GitHub token
                    git = {
                      user = {
                        name = "OpenClaw Agent";
                        email = "openclaw@funkymonkeymonk.dev";
                      };
                      github = {
                        token = "{file:/run/secrets/github-token}";
                      };
                    };
                    # All changes go through PR workflow
                    github = {
                      pr = {
                        enabled = true;
                        requireReview = true;
                        reviewers = ["funkymonkeymonk"];
                        draft = true;  # Start as draft PRs
                      };
                    };
                    # Use OpenCode Zen as the model provider
                    provider = {
                      opencode = {
                        npm = "@ai-sdk/openai-compatible";
                        name = "OpenCode Zen";
                        baseURL = "https://opencode.ai/zen/v1";
                        apiKey = "{file:/run/secrets/opencode-zen-apikey}";
                        models = [
                          "opencode/big-pickle"  # Free tier model
                          "opencode/claude-sonnet-4-5"
                          "opencode/gpt-5.2-codex"
                        ];
                      };
                    };
                    # Default model
                    model = "opencode/big-pickle";
                  };
                };
                
                # Configure opnix secrets from openclaw vault
                programs.onepassword-secrets = {
                  enable = true;
                  secrets = {
                    gatewayToken = {
                      reference = "op://openclaw/gateway-token/credential";
                      path = "/run/secrets/gateway-token";
                      mode = "0600";
                    };
                    githubToken = {
                      reference = "op://openclaw/github-pat/credential";
                      path = "/run/secrets/github-token";
                      mode = "0600";
                    };
                    opencodeZenApiKey = {
                      reference = "op://openclaw/opencode-zen-api-key/credential";
                      path = "/run/secrets/opencode-zen-apikey";
                      mode = "0600";
                    };
                  };
                };
                
                home.stateVersion = "25.05";
              };
              
              # systemd hardening
              systemd.services.openclaw-gateway = {
                serviceConfig = {
                  User = "openclaw";
                  Group = "openclaw";
                  
                  # Read-only access to cloned repo only
                  ReadOnlyPaths = ["/home/openclaw/nix"];
                  ReadWritePaths = ["/home/openclaw/nix/.git" "/tmp"];
                  PrivateTmp = true;
                  
                  # No access to system directories
                  PrivateDevices = true;
                  PrivateMounts = true;
                  
                  # Process restrictions
                  NoNewPrivileges = true;
                  ProtectSystem = "strict";
                  ProtectHome = true;
                  ProtectKernelTunables = true;
                  ProtectKernelModules = true;
                  ProtectControlGroups = true;
                  
                  # Resource limits
                  MemoryMax = "4G";
                  CPUQuota = "200%";
                  TasksMax = 100;
                };
              };
              
              # Initialize the nix repo on first boot
              systemd.services.openclaw-init = {
                description = "Initialize OpenClaw Nix Repository";
                after = ["network.target" "home-manager-openclaw.service"];
                wantedBy = ["multi-user.target"];
                serviceConfig = {
                  Type = "oneshot";
                  User = "openclaw";
                  RemainAfterExit = true;
                  Environment = [
                    "HOME=/home/openclaw"
                    "GITHUB_TOKEN_FILE=/run/secrets/github-token"
                  ];
                };
                script = ''
                  set -e
                  if [ ! -d /home/openclaw/nix ]; then
                    echo "Cloning ${targetRepo}..."
                    TOKEN=$(cat /run/secrets/github-token 2>/dev/null || echo "")
                    if [ -n "$TOKEN" ]; then
                      git clone "https://$TOKEN@github.com/${targetRepo}.git" /home/openclaw/nix
                    else
                      echo "Warning: No GitHub token available, clone will fail"
                      exit 1
                    fi
                    cd /home/openclaw/nix
                    git config user.name "OpenClaw Agent"
                    git config user.email "openclaw@funkymonkeymonk.dev"
                    echo "Repository cloned successfully"
                  else
                    echo "Repository already exists"
                  fi
                '';
              };
            })
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
      openclaw-secure = mkOpenclawMicrovm {
        name = "openclaw-secure";
        targetRepo = "funkymonkeymonk/nix";
      };
    };
  };
}
