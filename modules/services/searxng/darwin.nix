# SearXNG native launchd service for Darwin (macOS)
# Privacy-respecting metasearch engine
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.searxng;
  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "searxng";
  darwinHomeDir = "/Users/${primaryUser}";

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
  config = mkIf cfg.enable {
    launchd.daemons.searxng = {
      serviceConfig = {
        Label = "com.searxng.service";
        UserName = primaryUser;
        ProgramArguments = [
          "${pkgs.searxng}/bin/searxng-run"
        ];
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

    system.activationScripts.postActivation.text = mkAfter ''
      mkdir -p "${darwinHomeDir}/.local/share/searxng"
    '';
  };
}
