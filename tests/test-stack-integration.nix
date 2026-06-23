# LLM Stack Integration Test
# Validates that stack services (Bifrost + Caddy + dnsmasq + Vane + SearxNG)
# compose correctly and have consistent configuration.
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Evaluate the full stack as a module to check composition
  stackModule = {...}: {
    myConfig = {
      bifrost = {
        enable = true;
        logLevel = "debug";
        upstreams.vllm-mlx-local = {
          url = "http://localhost:8300";
          type = "openai";
          models = [
            "qwen3.6-35b"
          ];
        };
      };
      vane = {
        enable = true;
        openaiBaseUrl = "http://bifrost.internal/v1";
        defaultModel = "qwen3.6-35b";
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
      {
        # Stubs for options referenced by service modules
        options.environment = {
          etc = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
          };
          systemPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [];
          };
        };
        options.launchd.daemons = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
        };
        options.system.activationScripts = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
        };
      }
      ../modules/services/bifrost/darwin.nix
      ../modules/services/vane/darwin.nix
      ../modules/services/vane/common.nix
      ../modules/services/caddy/darwin.nix
    ];
  };

  cfg = eval.config.myConfig;

  # Verification checks
  checks = {
    servicesEnabled = cfg.bifrost.enable && cfg.caddy.enable && cfg.vane.enable;
    ports = cfg.bifrost.port == 8081 && cfg.caddy.port == 80 && cfg.vane.port == 3000;
    bifrostType = (builtins.head (builtins.attrValues cfg.bifrost.upstreams)).type == "openai";
    bifrostUrl = (builtins.head (builtins.attrValues cfg.bifrost.upstreams)).url == "http://localhost:8300";
    bifrostHasGemma = builtins.elem "qwen3.6-35b" (builtins.head (builtins.attrValues cfg.bifrost.upstreams)).models;
    vaneBaseUrl = cfg.vane.openaiBaseUrl == "http://bifrost.internal/v1";
    vaneDefaultModel = cfg.vane.defaultModel == "qwen3.6-35b";
  };

  allPass = builtins.all (v: v) (builtins.attrValues checks);
in {
  stackIntegrationTest =
    pkgs.runCommand "test-stack-integration"
    {}
    ''
      echo "=== LLM Stack Integration Test ==="
      echo ""
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: ''
          if [ "${builtins.toString value}" = "true" ]; then
            echo "  [PASS] ${name}"
          else
            echo "  [FAIL] ${name}"
          fi
        '')
        checks)}
      echo ""
      ${
        if allPass
        then ''echo "All stack integration checks passed."''
        else ''echo "Some checks FAILED!"; exit 1''
      }
      mkdir -p $out
      echo '${builtins.toJSON checks}' > $out/results.json
    '';
}
