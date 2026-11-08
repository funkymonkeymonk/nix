# MegamanX headless inference server machine configuration.
# The host runs only the local oMLX/Bifrost stack and Temporal.
{
  lib,
  mkUser,
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

  # The remote Nix daemon must trust its dedicated SSH user for ssh-ng builds.
  # Keep monkey trusted for interactive Nix use and isolate the builder key.
  nix.settings.trusted-users = ["root" "monkey" "nixbuilder"];

  imports = [
    ../../library/archetypes/headless-omlx-darwin.nix
  ];

  # This hidden staff account has no admin membership and only exposes the
  # Nix daemon protocol to Zero's dedicated builder key.
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

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      onepassword = {
        defaultVault = "Opnix";
        sudoPasswordRef = "op://Private/MegamanX Sudo Password/password";
      };
      ssh.enable = true;
      tailscale.enable = true;
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
      nodeExporter.listenOnTailscale = true;

      # oMLX serves the Nix-provided 4-bit Qwen checkpoint through its
      # continuous-batching and tiered KV-cache engine.
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

      roles.pi.enable = true;
      pi = {
        opencodeGoOnePasswordItem = "OpenCode Service Account - MegamanX/credential";
        jevOnePasswordItem = "OpenCode Service Account - MegamanX/credential";
        settings = {
          defaultProvider = "opencode-go";
        };
      };
      zellij.enable = true;
      llmClient = {
        serverHost = "127.0.0.1";
        serverPort = "8081";
      };

      bifrost = {
        enable = true;
        host = "127.0.0.1";
        exposeViaTailscaleServe = true;
        # UI for request tracing, logs, token analytics:
        #   http://localhost:8081/
        # Prometheus metrics: http://localhost:8081/metrics
        logLevel = "debug";
        upstreams = {
          omlx = {
            url = "http://localhost:8300";
            type = "anthropic";
            requestTimeout = 1800;
            streamIdleTimeoutInSeconds = 1800;
            maxRetries = 3;
            models = [
              "qwen3.8-27b"
            ];
          };
        };
      };

      searxng.enable = true;
      caddy.enable = true;

      temporal = {
        enable = true;
        ip = "0.0.0.0";
        uiIp = "0.0.0.0";
      };
    };

  # Start the Nix-darwin-managed Tailscale daemon at boot and recover it if it exits.
  services.tailscale.enable = true;
  launchd.daemons.tailscaled.serviceConfig.KeepAlive = true;

  # Keep password authentication available for monkey's interactive SSH access.
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
      temporal-cli
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
}
