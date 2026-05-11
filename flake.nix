{
  description = "Will Weaver system setup flake";

  nixConfig = {
    extra-experimental-features = ["flakes" "nix-command"];
  };

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

    # NEW: Takeout container infrastructure for automated installs
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    zellij-pane-tracker.url = "github:funkymonkeymonk/zellij-pane-tracker";

    # External skill repositories (Option 2: Pure Nix approach)
    vercel-skills.url = "github:vercel-labs/skills";
    vercel-skills.flake = false;

    # Sketchybar configuration with aerospace integration
    aerospace-sketchybar.url = "github:zmre/aerospace-sketchybar-nix-lua-config";

    # Official OpenClaw flake for declarative OpenClaw installation
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    nix-openclaw.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nix-darwin,
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    nix-homebrew,
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
          # zellij-pane-tracker WASM plugin from its own flake
          (final: _prev: {
            zellij-pane-tracker = inputs.zellij-pane-tracker.packages.${final.stdenv.hostPlatform.system}.default;
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
        enable = false;
      };
      llmClient.rtk.enable = true;
    };

    # Package overlays for each system
    forAllSystems = nixpkgs.lib.genAttrs [
      "aarch64-darwin"
      "x86_64-linux"
    ];

    # Helper to create microvm configuration
    # Secrets come from 1Password via opnix (host and guest both use it)
    mkMicrovm = name: roleEnables:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = inputs // {inherit roleEnables;};
        modules = [
          microvm.nixosModules.microvm
          home-manager.nixosModules.home-manager
          opnix.nixosModules.default
          configuration
          ./modules
          ./modules/nixos/base.nix
          ./modules/services/ollama/nixos.nix
          ./modules/services/openclaw
          inputs.nix-openclaw.nixosModules.openclaw-gateway
          ./os/microvm.nix
          ./modules/microvm
          ./targets/microvms/defaults.nix
          ./targets/microvms/${name}.nix
          {home-manager.sharedModules = [opnix.homeManagerModules.default];}
        ];
      };
  in {
    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import ./overlays)];
        };
      in
        {
          inherit (pkgs) rtk yaks;
          inherit (inputs.devenv.packages.${system}) devenv;
          installer = pkgs.callPackage ./packages/installer {};
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          # ISO installer only for x86_64-linux
          iso = self.nixosConfigurations.installer-iso.config.system.build.isoImage;
          # MicroVM declaration runners
          microvm-dev-vm = self.microvm.nixosConfigurations.dev-vm.config.microvm.declaredRunner;
          microvm-openclaw = self.microvm.nixosConfigurations.openclaw.config.microvm.declaredRunner;
          microvm-matrix = self.microvm.nixosConfigurations.matrix.config.microvm.declaredRunner;
          microvm-media-center = self.microvm.nixosConfigurations.media-center.config.microvm.declaredRunner;
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

    # ISO installer image (x86_64-linux only)
    nixosConfigurations.installer-iso = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./targets/installer-iso/default.nix
        {
          # Bundle the flake into the ISO for offline fallback
          isoImage.contents = [
            {
              source = ./.;
              target = "nix-flake";
            }
          ];
        }
      ];
    };

    darwinConfigurations = {
      "wweaver" = nix-darwin.lib.darwinSystem {
        specialArgs = {inherit inputs mkUser;};
        modules = [
          configuration
          nix-homebrew.darwinModules.nix-homebrew
          ./modules
          ./modules/roles/homebrew.nix
          ./modules/services/ollama/darwin.nix
          ./modules/services/vane/darwin.nix
          ./os/darwin.nix
          ./modules/home-manager/aerospace.nix
          ./targets/wweaver
          home-manager.darwinModules.home-manager
          {home-manager.sharedModules = [opnix.homeManagerModules.default];}
        ];
      };

      # Darwin server - headless macOS server for VM hosting
      # Uses Lume for macOS VMs, with Ollama for local LLMs
      "darwin-server" = nix-darwin.lib.darwinSystem {
        specialArgs = {inherit inputs mkUser;};
        modules = [
          configuration
          ./modules
          ./modules/services/lume/darwin.nix
          ./modules/services/ollama/darwin.nix
          ./os/darwin.nix
          ./targets/darwin-server
          home-manager.darwinModules.home-manager
          {
            home-manager.sharedModules = [
              opnix.homeManagerModules.default
              inputs.nix-openclaw.homeManagerModules.openclaw
            ];
          }
        ];
      };

      # Core configuration - absolute minimum for bootstrap/recovery
      # Uses only core.nix (git, curl, vim) - no foundation, no user config
      "core" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          ./modules/common/core.nix
          ./modules/common/options.nix
          ./targets/core
        ];
      };

      # MegamanX - personal desktop/workstation
      "MegamanX" = nix-darwin.lib.darwinSystem {
        specialArgs = {inherit inputs mkUser;};
        modules = [
          configuration
          nix-homebrew.darwinModules.nix-homebrew
          ./modules
          ./modules/roles/homebrew.nix
          ./modules/services/ollama/darwin.nix
          ./modules/services/vane/darwin.nix
          ./os/darwin.nix
          ./modules/home-manager/aerospace.nix
          ./targets/MegamanX
          home-manager.darwinModules.home-manager
          {home-manager.sharedModules = [opnix.homeManagerModules.default];}
        ];
      };
    };

    nixosConfigurations = {
      # Bootstrap configuration - minimal setup for initial install
      # Uses core.nix for absolute minimum, no foundation
      "bootstrap" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/common/core.nix
          ./targets/bootstrap
          ./modules/common/options.nix
          {
            nixpkgs.hostPlatform = "x86_64-linux";
            system.stateVersion = "25.05";
          }
        ];
      };

      "zero" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs mkUser;};
        modules = [
          configuration
          ./modules
          ./modules/nixos/base.nix
          ./modules/nixos/desktop.nix
          ./modules/nixos/gaming.nix
          ./modules/nixos/streaming.nix
          ./modules/services/ollama/nixos.nix
          ./modules/services/openclaw
          inputs.nix-openclaw.nixosModules.openclaw-gateway
          ./os/nixos.nix
          ./targets/zero
          home-manager.nixosModules.home-manager
          {
            home-manager.sharedModules = [
              opnix.homeManagerModules.default
              inputs.nix-openclaw.homeManagerModules.openclaw
            ];
          }

          # Disk layout
          inputs.disko.nixosModules.disko
          ./disk-configs/single-disk-ext4.nix

          # Machine type configuration (includes myConfig defaults and SSH keys)
          ./machine-types/desktop.nix

          # Ghostty terminfo for SSH support
          # https://github.com/ghostty-org/ghostty/discussions/5753
          ./modules/nixos/ghostty-terminfo.nix
        ];
      };

      # Foundation-based server configuration
      # Minimal required fields: system architecture, SSH authorized keys
      "type-server" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = inputs // {inherit inputs;};
        modules = [
          configuration
          microvm.nixosModules.microvm
          ./modules
          ./modules/nixos/base.nix
          home-manager.nixosModules.home-manager
          {home-manager.sharedModules = [opnix.homeManagerModules.default];}

          # Disk layout
          inputs.disko.nixosModules.disko
          ./disk-configs/single-disk-ext4.nix

          # Hardware detection via nixos-facter (module is in nixpkgs)
          # The facter.json file should be generated on the target machine
          # CI builds use --impure with a stub file

          # Machine type configuration (includes myConfig, hardware.facter, SSH keys)
          ./machine-types/server.nix

          # Official OpenClaw module
          inputs.nix-openclaw.nixosModules.openclaw-gateway
        ];
      };

      # ARM64 server variant
      "type-server-arm" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = inputs // {inherit inputs;};
        modules = [
          configuration
          microvm.nixosModules.microvm
          ./modules
          ./modules/nixos/base.nix
          home-manager.nixosModules.home-manager
          {home-manager.sharedModules = [opnix.homeManagerModules.default];}

          inputs.disko.nixosModules.disko
          ./disk-configs/single-disk-ext4.nix

          # Machine type configuration (includes myConfig, hardware.facter, SSH keys)
          ./machine-types/server-arm.nix
        ];
      };
    };

    microvm.nixosConfigurations = {
      dev-vm = mkMicrovm "dev-vm" {
        roles.opencode.enable = true;
      };
      openclaw = mkMicrovm "openclaw" {};
      matrix = mkMicrovm "matrix" {};
      media-center = mkMicrovm "media-center" {};
    };

    # Flake checks for CI - run on Linux and Darwin
    checks = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [(import ./overlays)];
        };
        tests = import ./tests {
          inherit pkgs self;
          inherit (nixpkgs) lib;
        };
        inherit (pkgs.stdenv.hostPlatform) isLinux;
      in
        {
          inherit
            (tests)
            foundation-options
            core-packages
            foundation-packages
            config-validation
            role-evaluation
            role-composition
            role-packages
            role-cascades
            llm-host-shared-models
            no-dead-development-option
            module-coverage
            skills-manifest
            skills-autoload-filtering
            skills-autoload-content
            skills-role-filtering
            skills-external-identification
            skills-external-command-generation
            skills-external-empty-case
            email-agent-options
            email-backup-options
            email-custom-options
            email-composition
            email-backup-scripts
            email-separation
            onepassword-guard
            onepassword-config-output
            zsh-enable-single-location
            sketchybar-options
            sketchybar-custom-options
            sketchybar-theme
            sketchybar-color-conversion
            sketchybar-platform-guard
            sketchybar-entrypoint
            ollama-options
            ollama-custom-options
            vane-options
            vane-custom-options
            openclaw-options
            jj-autosync-options
            jj-autosync-custom-options
            opencode-options
            opencode-custom-options
            shell-aliases
            workspace-switch
            fjj-options
            fjj-custom-options
            microvm-config
            microvm-jellyfin
            microvm-arr-services
            microvm-transmission
            microvm-nginx
            microvm-firewall
            microvm-ip-uniqueness
            microvm-ssh
            microvm-dev-vm-stateversion
            llm-client-opencode
            llm-client-claude
            llm-client-pi
            llm-client-custom-host
            llm-client-no-ai-roles
            entertainment-nixos
            typed-attrs-options
            ;
        }
        // nixpkgs.lib.optionalAttrs isLinux {
          inherit
            (tests)
            vm-users
            vm-ssh
            vm-packages
            ;
        }
    );
  };
}
