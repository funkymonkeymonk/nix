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

    # Bifrost AI Gateway - high-performance LLM gateway
    bifrost.url = "github:maximhq/bifrost";

    # Pi plugins - extensions and skills for pi coding agent
    pi-plugins.url = "github:funkymonkeymonk/pi-plugins";
    # Flake-parts (incremental migration — used for testing infrastructure first)
    flake-parts.url = "github:hercules-ci/flake-parts";

    # nix-unit: Eval-time unit testing framework
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.flake = false;

    # Himalaya TUI - terminal UI for email (companion to himalaya CLI)
    himalaya-tui.url = "github:pimalaya/himalaya-tui";
  };

  outputs = {
    self,
    nix-darwin,
    nixpkgs,
    home-manager,
    nix-homebrew,
    opnix,
    ...
  } @ inputs: let
    # Base configuration shared by all systems built via raw
    # nix-darwin.lib.darwinSystem / nixpkgs.lib.nixosSystem calls below
    # (MegamanX, zero, type-nas). Machines built via library/lib/mk-system.nix's
    # mkDarwinSystem/mkNixosSystem get the same core nixpkgs.config +
    # overlays from library/lib/nixpkgs-config.nix directly -- this
    # `configuration` binding layers a couple of extra overlays
    # (himalaya-tui, and an explicit claude-code allowUnfreePredicate,
    # currently redundant since allowUnfree = true already permits it)
    # on top of that shared module.
    configuration = _: {
      system.configurationRevision = self.rev or self.dirtyRev or null;
      nixpkgs = {
        config = {
          allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "claude-code"
            ];
        };
        overlays = [
          # himalaya-tui from upstream Pimalaya flake
          (final: _prev: {
            himalaya-tui = inputs.himalaya-tui.packages.${final.stdenv.hostPlatform.system}.default;
          })
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

    # Library helpers from the new modular library
    inherit (nixpkgs) lib;
    libraryLib = import ./library/lib/mk-system.nix {inherit lib;};
    mkNixpkgsConfigModule = import ./library/lib/nixpkgs-config.nix;
  in {
    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import ./overlays {inherit inputs;})];
        };
      in
        {
          inherit (pkgs) rtk yaks vane vllm-mlx mlx-vlm mlx-audio mlx-embeddings gemma4-31B-4bit gemma4-e4B-4bit;
          inherit (inputs.devenv.packages.${system}) devenv;
          installer = pkgs.callPackage ./packages/installer {};
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          # ISO installer only for x86_64-linux
          iso = self.nixosConfigurations.installer-iso.config.system.build.isoImage;
        }
    );

    apps = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import ./overlays {inherit inputs;})];
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
      # wweaver — work laptop (Will Weaver)
      # Uses mkDarwinSystem + developer-laptop-darwin + workstation-darwin archetypes
      "wweaver" = libraryLib.mkDarwinSystem {
        inherit inputs;
        hostname = "wweaver";
        extraSpecialArgs = {inherit mkUser;};
        modules = [
          ./library/archetypes/base-darwin.nix
          nix-homebrew.darwinModules.nix-homebrew
          ./library/archetypes/developer-laptop-darwin.nix
          ./library/archetypes/workstation-darwin.nix
          ./modules/services/vane/darwin.nix
          ./modules/services/bifrost/darwin.nix
          ./modules/home-manager/aerospace.nix
          ./hosts/wweaver
        ];
      };

      # darwin-server — headless macOS server for VM hosting
      # Uses libraryLib.mkDarwinSystem + headless-server-darwin archetype
      "darwin-server" = libraryLib.mkDarwinSystem {
        inherit inputs;
        hostname = "darwin-server";
        extraSpecialArgs = {inherit mkUser;};
        modules = [
          ./library/archetypes/headless-server-darwin.nix
          ./modules/services/lume/darwin.nix
          ./os/darwin.nix
          ./targets/darwin-server
          home-manager.darwinModules.home-manager
          {
            home-manager.sharedModules = [
              opnix.homeManagerModules.default
              inputs.nix-openclaw.homeManagerModules.openclaw
            ];
          }
          {
            nixpkgs.config.permittedInsecurePackages = [
              "olm-3.2.16"
            ];
          }
        ];
      };
      # MegamanX — personal desktop/workstation
      # Uses base-darwin archetype (modules, os/darwin, home-manager) +
      # workstation-darwin archetype (roles, ollama, pi) with machine-specific services
      "MegamanX" = nix-darwin.lib.darwinSystem {
        specialArgs = {inherit inputs mkUser;};
        modules = [
          configuration
          (mkNixpkgsConfigModule {inherit inputs;})
          ./library/archetypes/base-darwin.nix
          nix-homebrew.darwinModules.nix-homebrew
          ./library/archetypes/workstation-darwin.nix
          ./modules/services/vane/darwin.nix
          ./modules/services/bifrost/darwin.nix
          ./modules/services/searxng/darwin.nix
          ./modules/services/caddy/darwin.nix
          ./modules/services/vllm-mlx/darwin.nix
          ./modules/home-manager/aerospace.nix
          ./hosts/megamanx
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
          (mkNixpkgsConfigModule {inherit inputs;})
          opnix.nixosModules.default
          ./modules
          ./modules/nixos/base.nix
          ./modules/nixos/desktop.nix
          ./modules/nixos/gaming.nix
          ./modules/nixos/streaming.nix
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

          # Disk layout (zero-specific: NVMe, 1G ESP, 17G swap)
          inputs.disko.nixosModules.disko
          ./disk-configs/zero.nix

          # Machine type configuration (includes myConfig defaults and SSH keys)
          ./machine-types/desktop.nix

          # Ghostty terminfo for SSH support
          # https://github.com/ghostty-org/ghostty/discussions/5753
          ./modules/nixos/ghostty-terminfo.nix
        ];
      };

      # NAS - Network Attached Storage with ZFS and paperless-ngx
      "type-nas" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = inputs // {inherit inputs;};
        modules = [
          configuration
          (mkNixpkgsConfigModule {inherit inputs;})
          ./modules
          ./modules/nixos/base.nix
          home-manager.nixosModules.home-manager
          {home-manager.sharedModules = [opnix.homeManagerModules.default];}

          # Disk layout - ZFS for data redundancy
          inputs.disko.nixosModules.disko
          ./disk-configs/zfs-nas.nix

          # Machine type configuration (includes myConfig, hardware.facter, SSH keys)
          ./machine-types/server.nix

          # NAS-specific services (paperless, ZFS support)
          ./targets/type-nas
        ];
      };

      # CATTLE CONFIGURATIONS - Generic machine types
      # These require no hardware-configuration.nix!
      # Use with: ./scripts/install-machine.sh <type> <host> <disk>

      # Foundation-based server configuration
      # Minimal required fields: system architecture, SSH authorized keys
      # Uses libraryLib.mkNixosSystem + headless-server-nixos archetype
      "type-server" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "type-server";
        modules = [
          opnix.nixosModules.default
          ./modules/nixos/base.nix
          ./library/archetypes/headless-server-nixos.nix
          ./disk-configs/single-disk-ext4.nix
          inputs.nix-openclaw.nixosModules.openclaw-gateway
          {
            users.users.admin.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
            ];
          }
        ];
        overrides = {
          autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server";
        };
      };

      # ARM64 server variant
      # Uses libraryLib.mkNixosSystem + headless-server-nixos archetype
      "type-server-arm" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "type-server-arm";
        system = "aarch64-linux";
        modules = [
          opnix.nixosModules.default
          ./modules/nixos/base.nix
          ./library/archetypes/headless-server-nixos.nix
          ./disk-configs/single-disk-ext4.nix
          {
            users.users.admin.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
            ];
          }
          ({lib, ...}: {
            hardware.cpu.intel.updateMicrocode = lib.mkForce false;
            hardware.cpu.amd.updateMicrocode = lib.mkForce false;
          })
        ];
        overrides = {
          autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server-arm";
          tailscale.enable = false;
        };
      };

      # Phase 3: Real-machine migration — zero desktop/workstation
      # Parallel v2 config using new library mkNixosSystem + archetype.
      # Old nixosConfigurations.zero remains unchanged.
      "zero-v2" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "zero";
        extraSpecialArgs = {inherit mkUser;};
        modules = [
          ./modules/nixos/base.nix
          ./modules/nixos/desktop.nix
          ./modules/nixos/gaming.nix
          ./modules/nixos/streaming.nix
          ./modules/services/openclaw
          inputs.nix-openclaw.nixosModules.openclaw-gateway
          ./os/nixos.nix
          ./library/archetypes/desktop-nixos.nix
          inputs.disko.nixosModules.disko
          ./disk-configs/single-disk-ext4.nix
          ./modules/nixos/ghostty-terminfo.nix
          {
            home-manager.sharedModules = [
              inputs.nix-openclaw.homeManagerModules.openclaw
            ];
          }
          {
            nixpkgs.config.permittedInsecurePackages = [
              "openclaw-2026.4.22"
            ];
          }
          ./targets/zero
        ];
        overrides = {
          autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#zero-v2";
        };
      };

      # Uses libraryLib.mkNixosSystem + desktop-nixos archetype
      "type-desktop" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "type-desktop";
        modules = [
          opnix.nixosModules.default
          ./modules/nixos/base.nix
          ./modules/nixos/desktop.nix
          ./modules/nixos/ghostty-terminfo.nix
          ./library/archetypes/desktop-nixos.nix
          inputs.disko.nixosModules.disko
          ./disk-configs/single-disk-ext4.nix
          {
            users.users.root.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
            ];
          }
        ];
        overrides = {
          autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-desktop";
        };
      };
    };

    # Flake checks for CI - run on Linux and Darwin
    checks = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [(import ./overlays {inherit inputs;})];
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
            overlay-rtk
            overlay-yaks
            overlay-pi-coding-agent
            cross-platform-desktop-guard
            cross-platform-entertainment-guard
            cross-platform-creative-control
            config-validation
            all-role-tests
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
            aerospace-options
            aerospace-custom-options
            vane-options
            vane-custom-options
            vane-opnix-url-options
            vane-darwin-autostart-default
            vane-darwin-autostart-true
            opencode-options
            opencode-custom-options
            opencode-provider-opnix-url
            shell-aliases
            workspace-switch
            fjj-options
            fjj-custom-options
            vllm-mlx-options
            megamanx-vllm
            llm-client-opencode
            llm-client-claude
            llm-client-pi
            llm-client-custom-host
            llm-client-no-ai-roles
            typed-attrs-options
            stack-integration
            core-bootstrap
            phase3-zero
            phase4-darwin-server
            phase2-cattle
            mk-darwin-system
            mk-nixos-system
            claude-code-options
            claude-code-custom-options
            pi-options
            pi-custom-options
            bifrost-options
            bifrost-custom-options
            caddy-options
            caddy-custom-options
            searxng-options
            searxng-custom-options
            lume-options
            lume-custom-options
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
