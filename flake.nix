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

    # Bifrost AI Gateway - high-performance LLM gateway
    bifrost.url = "github:maximhq/bifrost";

    # Pi plugins - extensions and skills for pi coding agent
    pi-plugins.url = "github:funkymonkeymonk/pi-plugins";
    inference-worker.url = "github:funkymonkeymonk/inference-worker";
    # Flake-parts (incremental migration — used for testing infrastructure first)
    flake-parts.url = "github:hercules-ci/flake-parts";

    # nix-unit: Eval-time unit testing framework
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.flake = false;

    # Himalaya TUI - terminal UI for email (companion to himalaya CLI)
    himalaya-tui.url = "github:pimalaya/himalaya-tui";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["aarch64-darwin" "x86_64-linux"];
      imports = [
        ./library/flake-module.nix
        ./library/machines/zero.nix
        ./library/machines/darwin.nix
      ];
      flake = let
        # Package overlays for each system
        forAllSystems = nixpkgs.lib.genAttrs [
          "aarch64-darwin"
          "x86_64-linux"
        ];

        # Library helpers from the new modular library
        inherit (nixpkgs) lib;
        libraryLib = import ./library/lib/mk-system.nix {inherit lib;};
      in {
        lib = {
          optionsDoc = import ./scripts/generate-options-doc.nix {inherit lib self;};
        };

        packages = forAllSystems (
          system: let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [(import ./overlays {inherit inputs;})];
            };
          in
            {
              inherit (pkgs) rtk yaks lm-eval lighteval bfcl-eval bigcodebench evalscope openai-evals humaneval-mbpp;
              inherit (inputs.devenv.packages.${system}) devenv;
              installer = pkgs.callPackage ./packages/installer {};
            }
            // nixpkgs.lib.optionalAttrs (system == "aarch64-darwin") {
              inherit (pkgs) mlx-vlm mlx-audio mlx-embeddings gemma4-31B-4bit gemma4-e4B-4bit qwen3_8-27B-4bit qwen3_8-27B-mxfp4;
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
              ./modules/nixos/vector.nix
              ./modules/nixos/loki.nix
              ./modules/nixos/prometheus.nix
              ./modules/nixos/alertmanager.nix
              ./targets/type-server
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
              ./targets/type-server-arm
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
              ./targets/type-desktop
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
                temporal-options
                overlay-rtk
                overlay-yaks
                overlay-pi-coding-agent
                overlay-bigcodebench
                overlay-evalscope
                overlay-openai-evals
                overlay-humaneval-mbpp
                cross-platform-desktop-guard
                cross-platform-entertainment-guard
                cross-platform-creative-control
                config-validation
                zero-hardware-packages
                zero-steam-sdl-hidapi-env
                zero-cloud-only-config
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
                bfcl-package-metadata
                sketchybar-module-removed
                sketchybar-options-removed
                sketchybar-wiring-removed
                aerospace-options
                aerospace-custom-options
                opencode-options
                opencode-custom-options
                opencode-bifrost-defaults
                opencode-provider-opnix-url
                shell-aliases
                workspace-switch
                switch-task
                llm-client-opencode
                llm-client-claude
                llm-client-pi
                llm-client-custom-host
                llm-client-no-ai-roles
                typed-attrs-options
                core-bootstrap
                phase3-zero
                phase3-zero-flake-parts
                phase4-darwin-server
                phase2-cattle
                mk-darwin-system
                mk-nixos-system
                mk-user
                mk-user-calling-convention
                flake-module-args
                flake-module-library-export
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
                bifrost-anthropic-config
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
                prometheus-alerting-config
                vector-options
                vector-custom-options
                vector-generated-config
                loki-options
                loki-custom-options
                loki-generated-config
                alertmanager-options
                alertmanager-custom-options
                alertmanager-null-receiver
                grafana-options
                grafana-custom-options
                grafana-datasources
                grafana-federated-datasource
                nixos-vector-options
                nixos-vector-enabled
                nixos-vector-custom-endpoint
                nixos-loki-options
                nixos-loki-enabled
                nixos-loki-firewall
                type-server-log-aggregator
                nixos-prometheus-options
                nixos-node-exporter-options
                nixos-prometheus-enabled
                nixos-prometheus-alert-rules
                nixos-prometheus-alertmanager-wiring
                type-server-observability
                git-enable
                git-settings-exist
                git-commit-signing
                git-config-generation
                git-user-config
                obsidian-options
                obsidian-custom-options
                vm-role-generator
                ;
            }
            // nixpkgs.lib.optionalAttrs isDarwin {
              overlay-qwen38-mxfp4 = tests.overlay-qwen38-mxfp4;
            }
            // nixpkgs.lib.optionalAttrs isLinux {
              inherit
                (tests)
                vm-users
                vm-ssh
                vm-packages
                vm-role-foundation
                vm-role-developer
                ;
            }
        );
      };
    };
}
