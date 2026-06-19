# LLM Stack Integration Test
# Validates that all stack services (vMLX + Bifrost + Caddy + dnsmasq + Vane)
# compose correctly and have consistent configuration.
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Evaluate the full stack as a module to check composition
  stackModule = {config, ...}: {
    myConfig = {
      vmlx = {
        enable = true;
        server = {host = "0.0.0.0"; port = 8300;};
        model = {
          name = "mlx-community/gemma-4-12B-it-OptiQ-4bit";
          path = "mlx-community/gemma-4-12B-it-OptiQ-4bit";
        };
      };
      bifrost = {
        enable = true;
        logLevel = "debug";
        upstreams.vmlx-local = {
          url = "http://vmlx.internal";
          type = "openai";
          models = [
            "mlx-community/gemma-4-12B-it-OptiQ-4bit"
            "mlx-community/nomicai-modernbert-embed-base-4bit"
          ];
        };
      };
      vane = {
        enable = true;
        openaiBaseUrl = "http://bifrost.internal/v1";
        defaultModel = "mlx-community/gemma-4-12B-it-OptiQ-4bit";
        embeddingModel = "mlx-community/nomicai-modernbert-embed-base-4bit";
      };
      caddy = {enable = true;};
      searxng = {enable = true;};
    };
  };

  # Import all service modules
  eval = lib.evalModules {
    modules = [
      stackModule
      ../modules/common/options.nix
      ../modules/services/vmlx/darwin.nix
      ../modules/services/bifrost/darwin.nix
      ../modules/services/vane/darwin.nix
      ../modules/services/vane/common.nix
      ../modules/services/caddy/darwin.nix
    ];
  };

  cfg = eval.config.myConfig;

  # Verification checks
  checks = {
    servicesEnabled = cfg.vmlx.enable && cfg.bifrost.enable && cfg.caddy.enable && cfg.vane.enable;
    ports = cfg.vmlx.server.port == 8300 && cfg.bifrost.port == 8081 && cfg.caddy.port == 80 && cfg.vane.port == 3000;
    bifrostType = (builtins.head (builtins.attrValues cfg.bifrost.upstreams)).type == "openai";
    bifrostUrl = (builtins.head (builtins.attrValues cfg.bifrost.upstreams)).url == "http://vmlx.internal";
    bifrostHasGemma = builtins.elem "mlx-community/gemma-4-12B-it-OptiQ-4bit" (builtins.head (builtins.attrValues cfg.bifrost.upstreams)).models;
    bifrostHasEmbedding = builtins.elem "mlx-community/nomicai-modernbert-embed-base-4bit" (builtins.head (builtins.attrValues cfg.bifrost.upstreams)).models;
    vaneBaseUrl = cfg.vane.openaiBaseUrl == "http://bifrost.internal/v1";
    vaneDefaultModel = cfg.vane.defaultModel == "mlx-community/gemma-4-12B-it-OptiQ-4bit";
    vaneEmbeddingModel = cfg.vane.embeddingModel == "mlx-community/nomicai-modernbert-embed-base-4bit";
  };

  allPass = builtins.all (v: v) (builtins.attrValues checks);
in {
  stackIntegrationTest =
    pkgs.runCommand "test-stack-integration"
    {inherit checks;}
    ''
      echo "=== LLM Stack Integration Test ==="
      echo ""
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: ''
        if [ "${builtins.toString value}" = "true" ]; then
          echo "  [PASS] ${name}"
        else
          echo "  [FAIL] ${name}"
        fi
      '') checks)}
      echo ""
      ${if allPass then ''echo "All stack integration checks passed."'' else ''echo "Some checks FAILED!"; exit 1''}
      mkdir -p $out
      echo '${builtins.toJSON checks}' > $out/results.json
    '';
}
