# Charm CLI tools configuration
# Configures glow (markdown renderer) and mods (AI CLI) from charmbracelet
{
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.charm;
  glowCfg = cfg.glow;
  yamlFormat = pkgs.formats.yaml {};

  glowConfig = {
    inherit (glowCfg) style width pager mouse showLineNumbers preserveNewLines;
  };
in {
  config = mkIf cfg.enable {
    # glow: markdown renderer
    # home-manager has no native programs.glow, so we manage the config file directly.
    # On Darwin glow reads from ~/Library/Preferences/glow/glow.yml; on Linux it uses
    # $XDG_CONFIG_HOME/glow/glow.yml. We write both paths to cover all cases.
    home.packages = [pkgs.glow] ++ optional cfg.mods.enable pkgs.mods;

    xdg.configFile."glow/glow.yml".source = yamlFormat.generate "glow.yml" glowConfig;

    # Darwin: glow also reads from ~/Library/Preferences/glow/glow.yml
    home.file = mkIf pkgs.stdenv.hostPlatform.isDarwin {
      "Library/Preferences/glow/glow.yml".source = yamlFormat.generate "glow-darwin.yml" glowConfig;
    };

    # mods: AI on the command line (home-manager native support)
    programs.mods = mkIf cfg.mods.enable {
      enable = true;
      inherit (cfg.mods) settings;
    };
  };
}
