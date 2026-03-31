# Home Manager module for pi-coding-agent
# Manages pi configuration files in ~/.pi/agent/
{
  osConfig,
  lib,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.pi;
  hmLib = import ./lib.nix {inherit lib;};

  # Filter models that have 1Password items configured
  modelsWithSecrets = lib.filterAttrs (_name: model: model.onePasswordItem != "") cfg.models;

  # Build opnix secrets configuration
  opnixSecrets = hmLib.mkOpnixSecrets "pi" (
    lib.mapAttrs (name: model: {
      inherit (model) onePasswordItem;
      secretPath = ".pi/agent/secrets/${name}-apikey";
    })
    modelsWithSecrets
  );

  # Build models config with API key references
  modelsConfig =
    lib.mapAttrs (_name: model: {
      inherit (model) name provider modelId baseUrl;
      apiKey =
        if model.onePasswordItem != ""
        then "{file:~/.pi/agent/secrets/${_name}-apikey}"
        else model.apiKey;
    })
    cfg.models;

  # Core configuration files
  coreFiles = {
    ".pi/agent/settings.json" = mkIf (cfg.settings != {}) {
      text = builtins.toJSON cfg.settings;
    };
    ".pi/agent/AGENTS.md" = mkIf (cfg.agentsMd != "") {
      text = cfg.agentsMd;
    };
    ".pi/agent/SYSTEM.md" = mkIf (cfg.systemMd != "") {
      text = cfg.systemMd;
    };
    ".pi/agent/keybindings.json" = mkIf (cfg.keybindings != {}) {
      text = builtins.toJSON cfg.keybindings;
    };
    ".pi/agent/models.json" = mkIf (cfg.models != {}) {
      text = builtins.toJSON modelsConfig;
    };
  };

  # Prompt templates
  promptFiles = lib.mapAttrs' (name: content:
    lib.nameValuePair ".pi/agent/prompts/${name}.md" {
      text = content;
    })
  cfg.prompts;

  # Skills
  skillFiles = lib.mapAttrs' (name: content:
    lib.nameValuePair ".pi/agent/skills/${name}/SKILL.md" {
      text = content;
    })
  cfg.skills;

  # Extensions
  extensionFiles = lib.mapAttrs' (name: content:
    lib.nameValuePair ".pi/agent/extensions/${name}.ts" {
      text = content;
    })
  cfg.extensions;

  # Themes
  themeFiles = lib.mapAttrs' (name: theme:
    lib.nameValuePair ".pi/agent/themes/${name}.json" {
      text = builtins.toJSON theme;
    })
  cfg.themes;

  # All files merged together
  allFiles = coreFiles // promptFiles // skillFiles // extensionFiles // themeFiles;
in {
  config = mkIf cfg.enable {
    # All pi configuration files
    home.file = allFiles;

    # Configure opnix secrets for models with 1Password items
    programs.onepassword-secrets = mkIf (modelsWithSecrets != {} && osConfig.myConfig.onepassword.enable) {
      enable = true;
      secrets = opnixSecrets;
    };
  };
}
