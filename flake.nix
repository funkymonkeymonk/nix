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

    # Bifrost AI Gateway - high-performance LLM gateway
    bifrost.url = "github:maximhq/bifrost";
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
            "electron-39.8.10"
            "google-chrome-144.0.7559.97"
            "olm-3.2.16"
          ];
          allowInsecurePredicate = attrs: let
            pname = attrs.pname or attrs.name or "";
            fullName = "${pname}-${attrs.version or ""}";
          in
            pname
            == "openclaw"
            || builtins.elem fullName ["electron-39.8.10" "google-chrome-144.0.7559.97" "olm-3.2.16"];
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
          (import ./overlays {inherit inputs;})
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
    # Library helpers from the new modular library
    inherit (nixpkgs) lib;
    libraryLib = import ./library/lib/mk-system.nix {inherit lib;};

    # Phase 1: MicroVM v2 helper using new library mkNixosSystem
    _mkMicrovmV2 = name: roleEnables:
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
          # Resolve pre-existing shell conflict: base.nix sets shell for all
          # users from myConfig.users. When a VM target also sets shell for the
          # same user, both definitions at default priority conflict. Force the
          # VM target's shell to take precedence for the dev user.
          ({
            lib,
            pkgs,
            ...
          }: {
            users.users = lib.optionalAttrs (name == "dev-vm") {
              dev.shell = lib.mkForce pkgs.zsh;
            };
          })
        ];
      };
  in {
    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import ./overlays {inherit inputs;})];
        };
      in
        {
          inherit (pkgs) rtk yaks vane;
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
      "wweaver" = nix-darwin.lib.darwinSystem {
        specialArgs = {inherit inputs mkUser;};
        modules = [
          configuration
          nix-homebrew.darwinModules.nix-homebrew
          ./modules
          ./modules/roles/homebrew.nix
          ./modules/services/ollama/darwin.nix
          ./modules/services/vane/darwin.nix
          ./modules/services/bifrost/darwin.nix
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
          {
            nixpkgs.config.permittedInsecurePackages = [
              "olm-3.2.16"
            ];
          }
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

      # Phase 5: Core v2 — minimal config using raw darwinSystem
      # Uses raw nix-darwin.lib.darwinSystem (NOT mkDarwinSystem) intentionally.
      # Core is minimal — no home-manager, no opnix, no modules/ import.
      "core-v2" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          {
            networking.hostName = "core";
            system.configurationRevision = self.rev or self.dirtyRev or null;
            nixpkgs.hostPlatform = "aarch64-darwin";
            system.stateVersion = 4;
            nix.enable = false;
            myConfig = {
              users = [];
              roles = {};
              onepassword.enable = false;
              opencode.enable = false;
              agent-skills.enable = false;
            };
          }
          ./modules/common/core.nix
          ./modules/common/options.nix
        ];
      };

      # Phase 4: darwin-server v2 using new library mkDarwinSystem + headless-server-darwin archetype
      # Runs in parallel with darwin-server until verified.
      "darwin-server-v2" = libraryLib.mkDarwinSystem {
        inherit inputs;
        hostname = "darwin-server";
        extraSpecialArgs = {inherit mkUser;};
        modules = [
          ./library/archetypes/headless-server-darwin.nix
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
          {
            nixpkgs.config.permittedInsecurePackages = [
              "olm-3.2.16"
            ];
          }
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
          ./modules/services/bifrost/darwin.nix
          ./modules/services/searxng/darwin.nix
          ./modules/services/caddy/darwin.nix
          ./modules/services/ds4/darwin.nix
          ./modules/services/vmlx/darwin.nix
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

      # Phase 5: Bootstrap v2 — minimal config using raw nixosSystem
      # Uses raw nixpkgs.lib.nixosSystem (NOT mkNixosSystem) intentionally.
      # Bootstrap is intentionally minimal — no home-manager, no opnix, no disko.
      "bootstrap-v2" = nixpkgs.lib.nixosSystem {
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
          opnix.nixosModules.default
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

      "type-desktop" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = inputs // {inherit inputs;};
        modules = [
          configuration
          ./modules
          ./modules/nixos/base.nix
          home-manager.nixosModules.home-manager
          {home-manager.sharedModules = [opnix.homeManagerModules.default];}

          # Disk layout
          inputs.disko.nixosModules.disko
          ./disk-configs/zero.nix

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
          microvm.nixosModules.host
          opnix.nixosModules.default
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
          microvm.nixosModules.host
          opnix.nixosModules.default
          ./modules
          ./modules/nixos/base.nix
          home-manager.nixosModules.home-manager
          {home-manager.sharedModules = [opnix.homeManagerModules.default];}

          inputs.disko.nixosModules.disko
          ./disk-configs/single-disk-ext4.nix

          {
            hardware.cpu.intel.updateMicrocode = nixpkgs.lib.mkForce false;
            hardware.cpu.amd.updateMicrocode = nixpkgs.lib.mkForce false;
          }

          # Machine type configuration (includes myConfig, hardware.facter, SSH keys)
          ./machine-types/server-arm.nix
        ];
      };

      # Phase 1: MicroVM v2 configs using new library mkNixosSystem
      # Runs in parallel with microvm.nixosConfigurations until verified.
      "dev-vm-v2" = _mkMicrovmV2 "dev-vm" {
        roles.opencode.enable = true;
      };
      "openclaw-v2" = _mkMicrovmV2 "openclaw" {};
      "matrix-v2" = _mkMicrovmV2 "matrix" {};
      "media-center-v2" = _mkMicrovmV2 "media-center" {};

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
          ./modules/services/ollama/nixos.nix
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

      # Phase 2: Cattle NixOS v2 configs using new library mkNixosSystem
      # Runs in parallel with type-server and type-server-arm until verified.
      "type-server-v2" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "type-server";
        modules = [
          microvm.nixosModules.host
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
          autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server-v2";
        };
      };

      "type-server-arm-v2" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "type-server-arm";
        system = "aarch64-linux";
        modules = [
          microvm.nixosModules.host
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
          autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server-arm-v2";
          roles.tailscale.enable = false;
        };
      };

      "type-desktop-v2" = libraryLib.mkNixosSystem {
        inherit inputs;
        hostname = "type-desktop";
        modules = [
          opnix.nixosModules.default
          ./modules/nixos/base.nix
          ./modules/nixos/desktop.nix
          ./modules/nixos/ghostty-terminfo.nix
          ./library/archetypes/desktop-nixos.nix
          {
            users.users.root.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
            ];
          }
          {
            fileSystems."/" = {
              device = "/dev/null";
              fsType = "ext4";
            };
          }
        ];
        overrides = {
          autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-desktop-v2";
        };
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
            config-validation
            all-role-tests
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
            aerospace-options
            aerospace-custom-options
            ollama-options
            ollama-custom-options
            vane-options
            vane-custom-options
            vane-opnix-url-options
            openclaw-options
            jj-autosync-options
            jj-autosync-custom-options
            opencode-options
            opencode-custom-options
            opencode-provider-opnix-url
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
            ds4-options
            vmlx-options
            llm-client-opencode
            llm-client-claude
            llm-client-pi
            llm-client-custom-host
            llm-client-no-ai-roles
            entertainment-nixos
            typed-attrs-options
            phase5-core-bootstrap
            phase3-zero
            phase4-darwin-server
            phase2-cattle
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
