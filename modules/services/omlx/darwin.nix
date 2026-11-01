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
    (lib.escapeShellArg omlxPython)
    (lib.escapeShellArg omlxScript)
    "serve"
    "--model-dir ${lib.escapeShellArg modelDir}"
    "--host ${lib.escapeShellArg cfg.server.host}"
    "--port ${toString cfg.server.port}"
    "--log-level ${cfg.logLevel}"
    "--memory-guard-gb ${toString cfg.memoryGuardGb}"
    "--max-concurrent-requests ${toString cfg.maxConcurrentRequests}"
    "--paged-ssd-cache-dir ${lib.escapeShellArg cacheDir}"
    "--hot-cache-max-size ${lib.escapeShellArg cfg.hotCacheMaxSize}"
  ];
  # Keep Python as a child of a Nix-generated shell script. The shell also
  # supervises readiness because launchd KeepAlive cannot recover a process
  # that remains alive but never binds its API socket.
  readinessProbe = "http://${cfg.server.host}:${toString cfg.server.port}/health";
  readinessAttempts = toString (
    if cfg.startupTimeoutSeconds < 5
    then 1
    else builtins.div cfg.startupTimeoutSeconds 5
  );
  omlxCommand = pkgs.writeShellScript "omlx-launchd-service" ''
    set -euo pipefail
    export HOME=${lib.escapeShellArg darwinHomeDir}
    cd ${lib.escapeShellArg darwinHomeDir}

    ${omlxArguments} &
    server_pid=$!
    ready=0

    for attempt in $(/usr/bin/seq 1 ${readinessAttempts}); do
      if ! kill -0 "$server_pid" 2>/dev/null; then
        if wait "$server_pid"; then
          echo "oMLX exited before startup readiness" >&2
          exit 1
        else
          exit $?
        fi
      fi
      if ${pkgs.curl}/bin/curl --silent --fail --connect-timeout 2 --max-time 5 \
          ${lib.escapeShellArg readinessProbe} >/dev/null; then
        ready=1
        break
      fi
      /bin/sleep 5
    done

    if [ "$ready" -ne 1 ]; then
      echo "oMLX startup readiness timed out after ${toString cfg.startupTimeoutSeconds} seconds" >&2
      kill -TERM "$server_pid" 2>/dev/null || true
      wait "$server_pid" 2>/dev/null || true
      exit 1
    fi

    wait "$server_pid"
  '';
  metalToolchainMountPoint = "/Volumes/MetalToolchainCryptex";
  metalToolchainMountScript = ''
    set -eu

    assetRoot="/System/Library/AssetsV2/com_apple_MobileAsset_MetalToolchain"
    mountPoint="${metalToolchainMountPoint}"

    if /sbin/mount | /usr/bin/grep -Fq " on $mountPoint "; then
      exit 0
    fi

    /bin/mkdir -p "$mountPoint"

    latestDmg=$(
      /usr/bin/find "$assetRoot" -type f -name '*.dmg' -print 2>/dev/null \
        | while IFS= read -r dmg; do
            printf '%s %s\n' "$(/usr/bin/stat -f '%m' "$dmg")" "$dmg"
          done \
        | /usr/bin/sort -nr \
        | /usr/bin/sed -n '1s/^[0-9]* //p'
    )

    if [ -n "$latestDmg" ]; then
      /usr/bin/hdiutil attach "$latestDmg" -nobrowse -mountpoint "$mountPoint"
    fi
  '';
in {
  options.myConfig.omlx = {
    enable = lib.mkEnableOption "oMLX inference server";
    startupTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
      description = "Maximum time to wait for oMLX's health endpoint after launch before launchd restarts it.";
    };
    server = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Bind address for oMLX; keep it on loopback behind Bifrost.";
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
      default = 4;
      description = "Maximum concurrent oMLX requests; increase only after measuring queueing and memory pressure.";
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
    # No compatible oMLX package or upstream flake exists in this Nix input;
    # retain the upstream Homebrew formula but do not update it implicitly.
    homebrew.onActivation.autoUpdate = false;
    homebrew.onActivation.upgrade = false;
    homebrew.global.autoUpdate = false;
    homebrew.taps = [
      {
        name = "jundot/omlx";
        clone_target = "https://github.com/jundot/omlx";
        force_auto_update = false;
      }
    ];
    homebrew.brews = [
      {
        name = "jundot/omlx/omlx";
        args = ["with-custom-kernel"];
      }
    ];

    launchd.daemons.metal-toolchain-mount = {
      script = metalToolchainMountScript;
      serviceConfig = {
        Label = "org.omlx.metal-toolchain-mount";
        RunAtLoad = true;
        StartInterval = 300;
        WatchPaths = ["/Volumes"];
        StandardOutPath = "/tmp/omlx-metal-toolchain-mount.log";
        StandardErrorPath = "/tmp/omlx-metal-toolchain-mount.error.log";
      };
    };

    launchd.daemons.omlx = {
      command = omlxCommand;
      serviceConfig = {
        Label = "org.omlx.server";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = primaryUser;
        WorkingDirectory = darwinHomeDir;
        StandardOutPath = "${darwinHomeDir}/Library/Logs/omlx/server.log";
        StandardErrorPath = "${darwinHomeDir}/Library/Logs/omlx/server.error.log";
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          PATH = "/opt/homebrew/bin:/usr/bin:/bin";
          PYTHONUNBUFFERED = "1";
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
