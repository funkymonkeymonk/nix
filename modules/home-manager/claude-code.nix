{
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.claude-code;
  rtkCfg = osConfig.myConfig.llmClient.rtk;
  skillsCfg = osConfig.myConfig.skills or {};
  hmLib = import ./lib.nix {inherit lib;};

  # Filter MCP servers that have 1Password items configured for API keys
  mcpServersWithSecrets = lib.filterAttrs (_name: server: server.onePasswordItem != "") cfg.mcpServers;

  # Build opnix secrets configuration using shared helper
  opnixSecrets = hmLib.mkOpnixSecrets "claudeCode" osConfig.myConfig.onepassword.defaultVault (
    lib.mapAttrs (name: server: {
      inherit (server) onePasswordItem;
      secretPath = ".config/claude-code/secrets/${name}-apikey";
    })
    mcpServersWithSecrets
  );

  # Build MCP server config with API key references
  mcpServerConfig =
    lib.mapAttrs (name: server: {
      inherit (server) type;
      url = server.url or "";
      command = server.command or [];
      enabled = server.enabled or true;
      # Add API key from file if configured
      apiKey =
        if server.onePasswordItem != ""
        then "{file:~/.config/claude-code/secrets/${name}-apikey}"
        else server.apiKey or "";
    })
    cfg.mcpServers;

  # Build complete settings
  settings =
    {
      # Default settings
      inherit (cfg) includeCoAuthoredBy;
    }
    // cfg.extraSettings
    // (optionalAttrs (cfg.mcpServers != {}) {
      mcpServers = mcpServerConfig;
    });
  # Build auto-loaded skills content from manifest
  manifest = import ./skills/manifest.nix;
  enabledRoles = skillsCfg.enabledRoles or [];
  superpowersPath = skillsCfg.superpowersPath or null;
  enabledSkills =
    lib.filterAttrs (
      _name: skill:
        lib.any (role: lib.elem role skill.roles) enabledRoles
    )
    manifest;
  autoLoadSkills =
    lib.filterAttrs (
      _name: skill: skill.autoLoad or false
    )
    enabledSkills;
  autoLoadContent = lib.concatStringsSep "\n\n---\n\n" (lib.mapAttrsToList (
      name: skill: let
        skillMd =
          if skill.source.type == "internal"
          then let
            skillPath = skill.source.path + "/SKILL.md";
          in
            if builtins.pathExists skillPath
            then builtins.readFile skillPath
            else "# ${name}\n\n${skill.description}"
          else if skill.source.type == "superpowers" && superpowersPath != null
          then builtins.readFile "${superpowersPath}/skills/${skill.source.skillName}/SKILL.md"
          else "# ${name}\n\n${skill.description}";
      in
        skillMd
    )
    autoLoadSkills);
  hasAutoLoadSkills = autoLoadSkills != {};
in {
  config = mkIf cfg.enable {
    # RTK hook script - installed from rtk package when RTK is enabled
    home.file.".claude/hooks/rtk-rewrite.sh" = mkIf rtkCfg.enable {
      source = "${pkgs.rtk}/share/rtk/hooks/rtk-rewrite.sh";
      executable = true;
    };

    # Claude Code settings.json - managed manually to support hooks
    home.file.".claude/settings.json" = mkIf rtkCfg.enable {
      text = let
        fullSettings =
          settings
          // {
            hooks = {
              PreToolUse = [
                {
                  matcher = "Bash";
                  hooks = [
                    {
                      type = "command";
                      command = "~/.claude/hooks/rtk-rewrite.sh";
                    }
                  ];
                }
              ];
            };
          };
      in
        builtins.toJSON fullSettings;
    };

    # Auto-loaded skills injected into Claude Code session context
    home.file.".claude/CLAUDE.md" = mkIf hasAutoLoadSkills {
      text = autoLoadContent;
    };

    # Use home-manager's native programs.claude-code
    programs.claude-code = {
      enable = true;
      inherit settings;
      inherit (cfg) agents commands hooks;
    };

    # Configure opnix secrets for MCP servers with 1Password items
    programs.onepassword-secrets = mkIf (mcpServersWithSecrets != {} && osConfig.myConfig.onepassword.enable) {
      enable = true;
      secrets = opnixSecrets;
    };
  };
}
