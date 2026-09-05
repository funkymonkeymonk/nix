# oMLX inference server for Darwin (macOS).
# The runtime is installed by nix-darwin's Homebrew integration because the
# upstream project does not publish a Nix flake. Models remain Nix-managed.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.omlx;
  commonLib = import ../../common/lib.nix {inherit lib;};
  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  modelDir = "${darwinHomeDir}/.omlx/models";
  cacheDir = "${darwinHomeDir}/.omlx/cache";
  logDir = "${darwinHomeDir}/.omlx/logs";
  modelPath = "${pkgs.qwen3_8-27B-mxfp4}";
  # oMLX is an ARM-only formula, so it must use Homebrew's native ARM prefix.
  homebrewPrefix = "/opt/homebrew";
  omlxPython = "${homebrewPrefix}/opt/omlx/libexec/bin/python3.11";
  omlxScript = "${homebrewPrefix}/opt/omlx/libexec/bin/omlx";
  omlxArguments = lib.concatStringsSep " " [
    omlxPython
    omlxScript
    "serve"
    "--model-dir ${lib.escapeShellArg modelDir}"
    "--host ${lib.escapeShellArg cfg.server.host}"
    "--port ${toString cfg.server.port}"
    "--log-level ${cfg.logLevel}"
    "--memory-guard-gb ${toString cfg.memoryGuardGb}"
    "--max-concurrent-requests ${toString cfg.maxConcurrentRequests}"
    "--paged-ssd-cache-dir ${lib.escapeShellArg cacheDir}"
    "--hot-cache-max-size ${cfg.hotCacheMaxSize}"
  ];
  # Keep the signed system shell as the launchd child. Homebrew's Python
  # executable is ad-hoc signed and macOS 26 rejects it as a direct agent.
  omlxCommand = "/bin/sh -c ${lib.escapeShellArg omlxArguments}";
in {
  options.myConfig.omlx = {
    enable = lib.mkEnableOption "oMLX inference server";
    server = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Bind address for oMLX";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8300;
        description = "Port for oMLX's OpenAI-compatible API";
      };
    };
    logLevel = lib.mkOption {
      type = lib.types.enum ["trace" "debug" "info" "warning" "error"];
      default = "info";
      description = "oMLX log level";
    };
    memoryGuardGb = lib.mkOption {
      type = lib.types.ints.positive;
      default = 96;
      description = "Maximum oMLX process memory in GB";
    };
    maxConcurrentRequests = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Maximum concurrent oMLX requests";
    };
    hotCacheMaxSize = lib.mkOption {
      type = lib.types.str;
      default = "20GB";
      description = "In-memory oMLX hot cache size";
    };
  };

  config = lib.mkIf cfg.enable {
    homebrew.enable = true;
    homebrew.prefix = homebrewPrefix;
    homebrew.taps = [
      {
        name = "jundot/omlx";
        clone_target = "https://github.com/jundot/omlx";
      }
    ];
    homebrew.brews = [
      {
        name = "jundot/omlx/omlx";
      }
    ];

    launchd.user.agents.omlx = {
      command = omlxCommand;
      serviceConfig = {
        Label = "org.omlx.server";
        RunAtLoad = true;
        KeepAlive = true;
        WorkingDirectory = darwinHomeDir;
        StandardOutPath = "${darwinHomeDir}/Library/Logs/omlx/server.log";
        StandardErrorPath = "${darwinHomeDir}/Library/Logs/omlx/server.error.log";
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          PATH = "/opt/homebrew/bin:/usr/bin:/bin";
        };
      };
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      install -d "${darwinHomeDir}/.omlx"
      chown ${primaryUser}:staff "${darwinHomeDir}/.omlx"
      install -d -o ${primaryUser} -g staff "${modelDir}" "${cacheDir}" "${logDir}" "${darwinHomeDir}/Library/Logs/omlx"
      rm -f "${modelDir}/qwen3.8-27b"
      ln -s "${modelPath}" "${modelDir}/qwen3.8-27b"
      chown -h ${primaryUser}:staff "${modelDir}/qwen3.8-27b"
      if [ -f "${homebrewPrefix}/opt/omlx/libexec/lib/python3.11/site-packages/mlx/lib/libmlx.dylib" ]; then
        /usr/bin/codesign --force --sign - "${homebrewPrefix}/opt/omlx/libexec/lib/python3.11/site-packages/mlx/lib/libmlx.dylib"
      fi
    '';

    myConfig.serviceRegistry = commonLib.mkServiceRegistry "omlx" {
      displayName = "oMLX";
      port = cfg.server.port;
      label = "org.omlx.server";
      errorLog = "${darwinHomeDir}/Library/Logs/omlx/server.error.log";
      enabled = cfg.enable;
    };
  };
}
