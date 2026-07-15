# SearXNG native launchd service for Darwin (macOS)
# Privacy-respecting metasearch engine
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.searxng;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;

  # Use configured secret key or generate a stable one
  secretKey =
    if cfg.secretKey != ""
    then cfg.secretKey
    else builtins.hashString "sha256" "searxng-${toString cfg.port}";

  # Generate settings file
  settingsYml = pkgs.writeText "searxng-settings.yml" ''
    use_default_settings: true
    server:
      bind_address: "127.0.0.1"
      port: ${toString cfg.port}
      secret_key: "${secretKey}"
    search:
      formats:
        - html
        - json
    engines:
      - name: wolframalpha
        engine: wolframalpha
        shortcut: wa
        disabled: false
  '';
in {
  config = lib.mkIf cfg.enable {
    launchd.daemons.searxng = {
      command = "${pkgs.searxng}/bin/searxng-run";
      serviceConfig = {
        Label = "com.searxng.service";
        UserName = primaryUser;
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/searxng.log";
        StandardErrorPath = "/tmp/searxng.error.log";
        EnvironmentVariables = {
          SEARXNG_SETTINGS_PATH = "${settingsYml}";
        };
        WorkingDirectory = darwinHomeDir;
      };
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      mkdir -p "${darwinHomeDir}/.local/share/searxng"
    '';

    # Register in service registry for port conflict detection and readiness checks
    myConfig.serviceRegistry = commonLib.mkServiceRegistry "searxng" {
      displayName = "SearXNG";
      port = cfg.port;
      label = "com.searxng.service";
      errorLog = "/tmp/searxng.error.log";
      enabled = cfg.enable;
    };
  };
}
