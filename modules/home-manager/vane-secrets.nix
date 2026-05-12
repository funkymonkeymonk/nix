# Home-manager module for Vane opnix secrets
# Manages 1Password-backed secrets for the Vane service
# Imported automatically when myConfig.vane.openaiBaseUrlOpnixItem is set
{
  osConfig,
  lib,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.vane;
in {
  config = mkIf (cfg.enable && cfg.openaiBaseUrlOpnixItem != null && osConfig.myConfig.onepassword.enable) {
    programs.onepassword-secrets = {
      enable = true;
      secrets = {
        vaneOpenaiBaseUrl = {
          reference = cfg.openaiBaseUrlOpnixItem;
          path = ".config/vane/secrets/openai-base-url";
          mode = "0600";
        };
      };
    };
  };
}
