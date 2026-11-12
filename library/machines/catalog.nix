{
  inputs,
  generatedDirectory ? ./generated,
}: let
  mkCatalogMachine = import ./mk-catalog-machine.nix;
  mkUser = import ../lib/mk-user.nix;
  nixosMachine = mkCatalogMachine {kind = "nixos";};
  darwinMachine = mkCatalogMachine {
    kind = "darwin";
    extraSpecialArgs = {inherit mkUser;};
  };
  handMaintainedCatalog = {
    bootstrap = {
      kind = "nixos";
      secretProfile = "Personal";
      builder = "nixos";
      system = "x86_64-linux";
      hostname = null;
      modules = [
        ../../modules/common/core.nix
        ../../targets/bootstrap
        ../../modules/common/options.nix
      ];
      extraSpecialArgs = {};
      overrides = {};
    };

    type-nas = nixosMachine {
      secretProfile = "Opnix";
      disko = true;
      system = "x86_64-linux";
      hostname = "type-nas";
      nodeExporter.enable = true;
      modules = [
        ../archetypes/headless-server-nixos.nix
        ../../disk-configs/zfs-nas.nix
        ../../targets/hardware-facter.nix
        ../../machines/type-nas
      ];
      overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-nas";
    };

    type-server = nixosMachine {
      secretProfile = "Opnix";
      disko = true;
      system = "x86_64-linux";
      hostname = "type-server";
      nodeExporter.enable = true;
      modules = [
        ../archetypes/type-server.nix
        ../../disk-configs/single-disk-ext4.nix
        ../../targets/hardware-facter.nix
      ];
      overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server";
    };

    type-server-arm = nixosMachine {
      secretProfile = "Opnix";
      disko = true;
      system = "aarch64-linux";
      hostname = "type-server-arm";
      nodeExporter.enable = true;
      modules = [
        ../archetypes/type-server.nix
        ../../disk-configs/single-disk-ext4.nix
        ../../targets/hardware-facter.nix
        ../../machines/type-server-arm
      ];
      overrides = {
        autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server-arm";
        tailscale.enable = false;
      };
    };

    type-desktop = nixosMachine {
      secretProfile = "Personal";
      disko = true;
      system = "x86_64-linux";
      hostname = "type-desktop";
      modules = [
        ../archetypes/desktop-nixos.nix
        ../../modules/nixos/desktop.nix
        ../../modules/nixos/ghostty-terminfo.nix
        ../../disk-configs/single-disk-ext4.nix
        ../../targets/hardware-facter.nix
        ../../machines/type-desktop
      ];
      overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-desktop";
    };

    installer-iso = {
      kind = "nixos";
      secretProfile = "Personal";
      builder = "nixos";
      system = "x86_64-linux";
      hostname = null;
      modules = [
        ../../targets/installer-iso/default.nix
      ];
      extraSpecialArgs = {inherit inputs;};
      overrides = {};
    };

    zero = nixosMachine {
      secretProfile = "Opnix";
      disko = true;
      system = "x86_64-linux";
      hostname = "zero";
      modules = [
        ../archetypes/desktop-nixos.nix
        ../../modules/nixos/base.nix
        ../../modules/nixos/desktop.nix
        ../../modules/nixos/gaming.nix
        ../../modules/nixos/streaming.nix
        ../../modules/services/caddy/nixos.nix
        ../../os/nixos.nix
        ../../disk-configs/zero.nix
        ../archetypes/desktop-machine.nix
        ../../modules/nixos/ghostty-terminfo.nix
        ../../machines/zero
      ];
      extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
      overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#zero";
    };

    drlight = nixosMachine {
      secretProfile = "Opnix";
      disko = true;
      system = "x86_64-linux";
      hostname = "drlight";
      nodeExporter.enable = true;
      modules = [
        ../archetypes/type-media-center.nix
        ../archetypes/type-observability.nix
        ../../disk-configs/drlight.nix
        ../../modules/nixos/media-storage.nix
        ../../modules/nixos/media-management.nix
        ../../modules/nixos/ultra-media-download-stage.nix
        ../../modules/nixos/tailscale-home-dns.nix
        ../../modules/nixos/ghostty-terminfo.nix
        ../../machines/drlight
      ];
      extraSpecialArgs = {mkUser = import ../lib/mk-user.nix;};
      install.secrets."/etc/opnix/token" = {
        secret = "OPNIX_SERVICE_ACCOUNT_TOKEN";
        owner = "0:0";
        mode = "0600";
      };
      overrides = {
        autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#drlight";
        tailscale.authKeyMode = "devenv-oauth";
        tailscale.authKeyTags = ["tag:home-lab" "tag:media-center"];
      };
    };

    wweaver = darwinMachine {
      secretProfile = "Personal";
      system = "aarch64-darwin";
      hostname = "wweaver";
      modules = [
        ../../modules/services/bifrost/darwin.nix
        ../../modules/services/omlx/darwin.nix
        ../../modules/home-manager/aerospace.nix
        ../../machines/wweaver
      ];
    };

    MegamanX = darwinMachine {
      secretProfile = "MegamanX";
      system = "aarch64-darwin";
      hostname = "MegamanX";
      nodeExporter.enable = true;
      modules = [
        ../archetypes/headless-inference-darwin.nix
        ({
          lib,
          pkgs,
          ...
        }: let
          nixBuilderPublicKey =
            builtins.replaceStrings ["\n" "\r"] ["" ""]
            (builtins.readFile ../../keys/nix-remote-builder-megamanx.pub);
          nixBuilderAuthorizedKey = "restrict,command=\"/nix/var/nix/profiles/default/bin/nix-daemon --stdio\" ${nixBuilderPublicKey}";
        in {
          system.stateVersion = 4;
          system.primaryUser = "monkey";

          nix.settings.trusted-users = ["root" "monkey" "nixbuilder"];

          # This hidden account exposes only the Nix daemon protocol to Zero's builder key.
          users.knownUsers = ["nixbuilder"];
          users.users.nixbuilder = {
            uid = 502;
            gid = 20;
            description = "Nix remote builder for Zero";
            home = "/var/empty";
            shell = pkgs.bashInteractive;
            ignoreShellProgramCheck = true;
            isHidden = true;
            createHome = false;
            openssh.authorizedKeys.keys = [nixBuilderAuthorizedKey];
          };

          services.tailscale.enable = true;
          launchd.daemons.tailscaled.serviceConfig.KeepAlive = true;

          services.openssh.extraConfig = lib.mkForce ''
            PermitRootLogin no
            PubkeyAuthentication yes
            PasswordAuthentication yes
            AllowAgentForwarding yes

            Match User nixbuilder
              AuthenticationMethods publickey
              PasswordAuthentication no
              KbdInteractiveAuthentication no
              AllowAgentForwarding no
              AllowTcpForwarding no
              PermitTTY no
              X11Forwarding no
              ForceCommand /nix/var/nix/profiles/default/bin/nix-daemon --stdio

            Match all
          '';

          environment.systemPackages = with pkgs;
            [
              clang
              python3
              nodejs
              yarn
              gh-dash
              slidev-cli
              mergiraf
            ]
            ++ lib.optional (pkgs ? yaks) pkgs.yaks;

          environment.shellAliases = {
            yl = "yx ls";
            yla = "yx ls --all";
            ya = "yx add";
            yd = "yx done";
            ys = "yx sync";
          };
        })
      ];
      overrides =
        mkUser "monkey" "me@willweaver.dev"
        // {
          onepassword = {
            defaultVault = "Opnix";
            sudoPasswordRef = "op://Private/MegamanX Sudo Password/password";
          };
          ssh.enable = true;
          tailscale.enable = true;
          nodeExporter.listenOnTailscale = true;
          collector.destinationHostname = "drlight";
          vector = {
            enable = true;
            hostLabel = "MegamanX";
            logGlobs = [
              "/tmp/*.log"
              "/Users/monkey/Library/Logs/omlx/*.log"
              "/Users/monkey/.omlx/logs/*.log"
            ];
          };

          omlx = {
            enable = true;
            server = {
              host = "127.0.0.1";
              port = 8300;
            };
            logLevel = "info";
            memoryGuardGb = 96;
            maxConcurrentRequests = 4;
            hotCacheMaxSize = "20GB";
          };

          pi = {
            opencodeGoOnePasswordItem = "OpenCode Service Account - MegamanX/credential";
            jevOnePasswordItem = "OpenCode Service Account - MegamanX/credential";
            settings = {
              defaultProvider = "opencode-go";
            };
          };
          llmClient = {
            serverHost = "127.0.0.1";
            serverPort = "8081";
          };

          bifrost = {
            enable = true;
            host = "127.0.0.1";
            exposeViaTailscaleServe = true;
            logLevel = "debug";
            upstreams = {
              omlx = {
                url = "http://localhost:8300";
                type = "anthropic";
                requestTimeout = 1800;
                streamIdleTimeoutInSeconds = 1800;
                maxRetries = 3;
                models = ["qwen3.8-27b"];
              };
            };
          };

          searxng.enable = true;
          caddy.enable = true;
        };
    };
  };
  generatedCatalog = import ./load-generated-catalog.nix {
    directory = generatedDirectory;
    inherit darwinMachine nixosMachine;
    existingCatalog = handMaintainedCatalog;
  };
in
  handMaintainedCatalog // generatedCatalog
