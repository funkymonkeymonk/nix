# Higgs LLM inference server option and service tests
# Validates option defaults, custom values, and TOML config generation
{pkgs, ...}: let
  inherit (pkgs) lib;

  stubModules = [
    ../modules/common/options.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  # Evaluate with defaults
  higgsDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.higgs;

  # Evaluate with custom values
  higgsCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.higgs = {
              enable = true;
              server = {
                host = "127.0.0.1";
                port = 9000;
                maxTokens = 16384;
                timeout = 600.0;
                maxBodySize = 20971520;
                rateLimit = 100;
              };
              local = {
                mlxProfile = "throughput";
                raiseWiredLimit = true;
              };
              models = [
                {
                  path = "mlx-community/Qwen3-1.7B-4bit";
                  name = "qwen";
                  mlxProfile = "balanced";
                }
              ];
              providers = {
                anthropic = {
                  url = "https://api.anthropic.com";
                  format = "anthropic";
                };
              };
              routes = [
                {
                  pattern = "claude-.*";
                  provider = "anthropic";
                }
              ];
              autoRouter = {
                enable = true;
                model = "qwen";
                timeoutMs = 3000;
              };
            };
          }
        ];
    }).config.myConfig.higgs;

  # Verify TOML generation via the home-manager module
  tomlFormat = pkgs.formats.toml {};

  testTomlConfig = {
    server = {
      host = "127.0.0.1";
      port = 9000;
    };
    local = {
      mlx_profile = "throughput";
      raise_wired_limit = true;
    };
    models = [
      {
        path = "mlx-community/Qwen3-1.7B-4bit";
        name = "qwen";
        mlx_profile = "balanced";
      }
    ];
    provider.anthropic = {
      url = "https://api.anthropic.com";
      format = "anthropic";
    };
    routes = [
      {
        pattern = "claude-.*";
        provider = "anthropic";
      }
    ];
    default.provider = "higgs";
    auto_router = {
      enabled = true;
      model = "qwen";
      timeout_ms = 3000;
    };
  };

  generatedToml = builtins.readFile (tomlFormat.generate "test-config.toml" testTomlConfig);
in {
  higgsOptionsTest =
    pkgs.runCommand "test-higgs-options"
    {}
    ''
      echo "=== Testing Higgs Option Defaults ==="

      ${
        if !higgsDefaults.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if higgsDefaults.server.host == "0.0.0.0"
        then ''echo "  server.host default = 0.0.0.0: OK"''
        else ''echo "  server.host should default to 0.0.0.0!"; exit 1''
      }

      ${
        if higgsDefaults.server.port == 8000
        then ''echo "  server.port default = 8000: OK"''
        else ''echo "  server.port should default to 8000!"; exit 1''
      }

      ${
        if higgsDefaults.server.maxTokens == null
        then ''echo "  server.maxTokens default = null: OK"''
        else ''echo "  server.maxTokens should default to null!"; exit 1''
      }

      ${
        if higgsDefaults.server.timeout == null
        then ''echo "  server.timeout default = null: OK"''
        else ''echo "  server.timeout should default to null!"; exit 1''
      }

      ${
        if higgsDefaults.local.mlxProfile == "auto"
        then ''echo "  local.mlxProfile default = auto: OK"''
        else ''echo "  local.mlxProfile should default to auto!"; exit 1''
      }

      ${
        if higgsDefaults.local.raiseWiredLimit == false
        then ''echo "  local.raiseWiredLimit default = false: OK"''
        else ''echo "  local.raiseWiredLimit should default to false!"; exit 1''
      }

      ${
        if higgsDefaults.models == []
        then ''echo "  models default = []: OK"''
        else ''echo "  models should default to empty list!"; exit 1''
      }

      ${
        if higgsDefaults.providers == {}
        then ''echo "  providers default = {}: OK"''
        else ''echo "  providers should default to empty attrset!"; exit 1''
      }

      ${
        if higgsDefaults.routes == []
        then ''echo "  routes default = []: OK"''
        else ''echo "  routes should default to empty list!"; exit 1''
      }

      ${
        if higgsDefaults.default.provider == "higgs"
        then ''echo "  default.provider default = higgs: OK"''
        else ''echo "  default.provider should default to higgs!"; exit 1''
      }

      ${
        if higgsDefaults.autoRouter.enable == false
        then ''echo "  autoRouter.enable default = false: OK"''
        else ''echo "  autoRouter.enable should default to false!"; exit 1''
      }

      ${
        if higgsDefaults.retention.enable == true
        then ''echo "  retention.enable default = true: OK"''
        else ''echo "  retention.enable should default to true!"; exit 1''
      }

      ${
        if higgsDefaults.logging.metrics.enable == true
        then ''echo "  logging.metrics.enable default = true: OK"''
        else ''echo "  logging.metrics.enable should default to true!"; exit 1''
      }

      echo ""
      echo "=== Testing Higgs Custom Options ==="

      ${
        if higgsCustom.server.host == "127.0.0.1"
        then ''echo "  server.host = 127.0.0.1: OK"''
        else ''echo "  server.host should be 127.0.0.1!"; exit 1''
      }

      ${
        if higgsCustom.server.port == 9000
        then ''echo "  server.port = 9000: OK"''
        else ''echo "  server.port should be 9000!"; exit 1''
      }

      ${
        if higgsCustom.server.maxTokens == 16384
        then ''echo "  server.maxTokens = 16384: OK"''
        else ''echo "  server.maxTokens should be 16384!"; exit 1''
      }

      ${
        if higgsCustom.local.mlxProfile == "throughput"
        then ''echo "  local.mlxProfile = throughput: OK"''
        else ''echo "  local.mlxProfile should be throughput!"; exit 1''
      }

      ${
        if higgsCustom.local.raiseWiredLimit == true
        then ''echo "  local.raiseWiredLimit = true: OK"''
        else ''echo "  local.raiseWiredLimit should be true!"; exit 1''
      }

      ${
        if builtins.length higgsCustom.models == 1
        then ''echo "  models count = 1: OK"''
        else ''echo "  models should have 1 entry!"; exit 1''
      }

      ${
        if builtins.hasAttr "anthropic" higgsCustom.providers
        then ''echo "  providers includes anthropic: OK"''
        else ''echo "  providers should include anthropic!"; exit 1''
      }

      ${
        if builtins.length higgsCustom.routes == 1
        then ''echo "  routes count = 1: OK"''
        else ''echo "  routes should have 1 entry!"; exit 1''
      }

      ${
        if higgsCustom.autoRouter.enable == true
        then ''echo "  autoRouter.enable = true: OK"''
        else ''echo "  autoRouter.enable should be true!"; exit 1''
      }

      ${
        if higgsCustom.autoRouter.model == "qwen"
        then ''echo "  autoRouter.model = qwen: OK"''
        else ''echo "  autoRouter.model should be qwen!"; exit 1''
      }

      echo ""
      echo "=== Testing TOML Generation ==="

      ${
        if builtins.match ".*host = \"127.0.0.1\".*" generatedToml != null
        then ''echo "  TOML contains host: OK"''
        else ''echo "  TOML should contain host!"; exit 1''
      }

      ${
        if builtins.match ".*port = 9000.*" generatedToml != null
        then ''echo "  TOML contains port: OK"''
        else ''echo "  TOML should contain port!"; exit 1''
      }

      ${
        if builtins.match ".*mlx_profile = \"throughput\".*" generatedToml != null
        then ''echo "  TOML contains mlx_profile: OK"''
        else ''echo "  TOML should contain mlx_profile!"; exit 1''
      }

      ${
        if builtins.match ".*provider = \"higgs\".*" generatedToml != null
        then ''echo "  TOML contains default provider: OK"''
        else ''echo "  TOML should contain default provider!"; exit 1''
      }

      echo ""
      echo "All Higgs option and config tests passed"
      touch $out
    '';
}
