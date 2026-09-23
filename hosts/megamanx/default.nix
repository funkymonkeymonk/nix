# MegamanX headless inference server target configuration.
# The host runs only the local oMLX/Bifrost stack and Temporal.
{
  lib,
  mkUser,
  pkgs,
  ...
}: let
  gomuks = builtins.tryEval pkgs.gomuks;
in {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "monkey";

  imports = [
    ../../library/archetypes/headless-omlx-darwin.nix
  ];

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      # oMLX serves the Nix-provided 4-bit Qwen checkpoint through its
      # continuous-batching and tiered KV-cache engine.
      omlx = {
        enable = true;
        server = {
          host = "0.0.0.0";
          port = 8300;
        };
        logLevel = "info";
        memoryGuardGb = 96;
        maxConcurrentRequests = 8;
        hotCacheMaxSize = "20GB";
      };

      roles.pi.enable = true;
      zellij.enable = true;
      llmClient = {
        serverHost = "127.0.0.1";
        serverPort = "8081";
      };

      bifrost = {
        enable = true;
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

      temporal = {
        enable = true;
        ip = "0.0.0.0";
        uiIp = "0.0.0.0";
      };
    };

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
    ++ lib.optional gomuks.success gomuks.value
    ++ lib.optional (pkgs ? yaks) pkgs.yaks;

  environment.shellAliases = {
    yl = "yx ls";
    yla = "yx ls --all";
    ya = "yx add";
    yd = "yx done";
    ys = "yx sync";
  };
}
