# MegamanX headless inference server target configuration.
# The host runs only the local oMLX/Bifrost stack and Temporal.
{
  lib,
  mkUser,
  pkgs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "monkey";

  imports = [
    ../../library/archetypes/headless-omlx-darwin.nix
  ];

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
        opencodeGoOnePasswordItem = "Opencode/Service Accounts/MegamanX";
        jevOnePasswordItem = "Opencode/Service Accounts/MegamanX";
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

  # Preserve the currently working password-based SSH path until key-based
  # access is explicitly provisioned for this host.
  services.openssh.extraConfig = lib.mkForce ''
    PermitRootLogin no
    PubkeyAuthentication yes
    PasswordAuthentication yes
    AllowAgentForwarding yes
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
