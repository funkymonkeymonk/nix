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
    nixpkgs,
    ...
  } @ inputs: let
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
  in {
    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import ./overlays {inherit inputs;})];
        };
      in
        {
          inherit (pkgs) rtk yaks vane vllm-mlx mlx-vlm mlx-audio mlx-embeddings gemma4-31B-4bit gemma4-e4B-4bit qwen3_8-27B-8bit qwen3_8-27B-4bit qwen3_8-27B-MTP-8bit qwen3_8-27B-MTP-4bit lm-eval lighteval;
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
      # Composed from workstation-darwin archetype + machine-specific overrides.
      "wweaver" = libraryLib.mkDarwinSystem {
        inherit inputs;
        hostname = "wweaver";
        extraSpecialArgs = {inherit mkUser;};
        modules = [
          ./library/archetypes/workstation-darwin.nix
          ./modules/services/vane/darwin.nix
          ./modules/services/bifrost/darwin.nix
          ./modules/home-manager/aerospace.nix
          ./hosts/wweaver
        ];
      };

      # darwin-server — headless macOS server for VM hosting
      # Composed from headless-server-darwin archetype + machine-specific overrides.
      "darwin-server" = libraryLib.mkDarwinSystem {
        inherit inputs;
        hostname = "darwin-server";
        extraSpecialArgs = {inherit mkUser;};
        modules = [
          ./library/archetypes/headless-server-darwin.nix
          {
            nixpkgs.config.permittedInsecurePackages = [
              "olm-3.2.16"
            ];
          }
          ./hosts/darwin-server
        ];
      };
      # MegamanX — personal desktop/workstation
      # Composed from workstation-darwin archetype + local LLM stack services.
      "MegamanX" = libraryLib.mkDarwinSystem {
        inherit inputs;
        hostname = "MegamanX";
        extraSpecialArgs = {inherit mkUser;};
        modules = [
          ./library/archetypes/workstation-darwin.nix
          ./modules/services/vane/darwin.nix
          ./modules/services/bifrost/darwin.nix
          ./modules/services/searxng/darwin.nix
          ./modules/services/caddy/darwin.nix
          ./modules/services/vllm-mlx/darwin-instances-options.nix
          ./modules/services/vllm-mlx/darwin.nix
          ./modules/services/vllm-mlx/darwin-instances-config.nix
          ./modules/services/prometheus/darwin.nix
          ./modules/services/node-exporter/darwin.nix
          ./modules/home-manager/aerospace.nix
          ./hosts/megamanx
        ];
      };

      # type-darwin-server — generic headless macOS server template
      # Composed from headless-server-darwin archetype + minimal overrides.
      "type-darwin-server" = libraryLib.mkDarwinSystem {
        inherit inputs;
        hostname = "type-darwin-server";
        extraSpecialArgs = {inherit mkUser;};
        modules = [
          ./library/archetypes/headless-server-darwin.nix
          ./targets/type-darwin-server
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

      # zero — Gaming/desktop NixOS machine
      # Composed from desktop-nixos archetype + machine-specific modules.
      "zero" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "zero";
        extraSpecialArgs = {inherit mkUser;};
        modules = [
          ./library/archetypes/desktop-nixos.nix
          ./modules/nixos/base.nix
          ./modules/nixos/desktop.nix
          ./modules/nixos/gaming.nix
          ./modules/nixos/streaming.nix
          ./os/nixos.nix
          inputs.disko.nixosModules.disko
          ./disk-configs/zero.nix
          ./machine-types/desktop.nix
          ./modules/nixos/ghostty-terminfo.nix
          ./targets/zero
        ];
        overrides = {
          autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#zero";
        };
      };

      # NAS - Network Attached Storage with ZFS and paperless-ngx
      # Composed from headless-server-nixos archetype + NAS-specific overrides.
      "type-nas" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "type-nas";
        modules = [
          ./library/archetypes/headless-server-nixos.nix
          inputs.disko.nixosModules.disko
          ./disk-configs/zfs-nas.nix
          ./targets/type-nas
        ];
        overrides = {
          autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-nas";
        };
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
          ./library/archetypes/headless-server-nixos.nix
          ./disk-configs/single-disk-ext4.nix
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

      # Uses libraryLib.mkNixosSystem + desktop-nixos archetype
      "type-desktop" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "type-desktop";
        modules = [
          ./library/archetypes/desktop-nixos.nix
          ./modules/nixos/desktop.nix
          ./modules/nixos/ghostty-terminfo.nix
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
        inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
      in
        {
          inherit
            (tests)
            nix-unit-tests
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
            vllm-mlx-launchd
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
            fjj-mirror-root-default
            fjj-custom-mirror-root
            fjj-package-and-files
            agent-user-options
            agent-user-disabled
            agent-user-enabled
            agent-user-custom
            claude-code-options
            claude-code-custom-options
            pi-options
            pi-custom-options
            bifrost-options
            bifrost-custom-options
            bifrost-retry-config
            caddy-options
            caddy-custom-options
            searxng-options
            searxng-custom-options
            lume-options
            lume-custom-options
            node-exporter-options
            node-exporter-custom-options
            prometheus-options
            prometheus-custom-options
            prometheus-generated-script
            prometheus-scrape-config
            git-enable
            git-settings-exist
            git-commit-signing
            git-config-generation
            git-user-config
            obsidian-options
            obsidian-custom-options
            ;
        }
        // nixpkgs.lib.optionalAttrs isDarwin {
          # Builds the darwin-only vllm-mlx package; excluded on Linux.
          inherit (tests) vllm-mlx-finish-reason;
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
