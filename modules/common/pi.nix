# myConfig.pi options — owned here, consumed by
# modules/home-manager/pi-coding-agent.nix (loaded conditionally via
# modules/common/users.nix) and set by modules/roles/pi.nix.
{lib, ...}: {
  options.myConfig.pi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable pi coding agent configuration management";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = ''
        Pi settings.json configuration.
        See https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/settings.md
        for available options.
      '';
    };

    agentsMd = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Global AGENTS.md content. This is loaded at startup from ~/.pi/agent/AGENTS.md
        and provides project-agnostic instructions to pi.
      '';
    };

    systemMd = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Custom system prompt content. Written to ~/.pi/agent/SYSTEM.md.
        Replaces the default system prompt. Use APPEND_SYSTEM.md to append instead.
      '';
    };

    keybindings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = ''
        Custom keybindings configuration.
        Keys are action names, values are key combinations.
        See https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/keybindings.md
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name for the model";
          };
          provider = lib.mkOption {
            type = lib.types.str;
            description = "Provider ID (e.g., 'anthropic', 'openai', 'ollama')";
          };
          modelId = lib.mkOption {
            type = lib.types.str;
            description = "Model identifier (e.g., 'claude-sonnet-4-6', 'gpt-4o')";
          };
          apiKey = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "API key for the model (use onePasswordItem for secrets)";
          };
          onePasswordItem = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "1Password item reference (e.g., 'op://vault/item/field')";
          };
          baseUrl = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Base URL for the API (for custom endpoints)";
          };
          reasoning = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether the model supports extended thinking/reasoning";
          };
          maxTokens = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Maximum output tokens for the model";
          };
          compat = lib.mkOption {
            type = lib.types.attrsOf (lib.types.oneOf [lib.types.bool lib.types.str]);
            default = {};
            description = ''
              Compatibility settings for the model provider.
              Common keys: supportsDeveloperRole, supportsReasoningEffort,
              supportsUsageInStreaming, maxTokensField, thinkingFormat.
              Set supportsDeveloperRole = false for local OpenAI-compatible
              servers that do not understand the "developer" role.
            '';
          };
        };
      });
      default = {};
      description = ''
        Custom models configuration for ~/.pi/agent/models.json.
        Allows adding custom providers and models.
      '';
    };

    prompts = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
      description = ''
        Prompt templates as attribute set.
        Each key is the prompt name, value is the template content.
        Written to ~/.pi/agent/prompts/<name>.md
      '';
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
      description = ''
        Skills as attribute set.
        Each key is the skill name, value is the SKILL.md content.
        Written to ~/.pi/agent/skills/<name>/SKILL.md
      '';
    };

    extensions = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
      description = ''
        Extensions as attribute set.
        Each key is the extension name, value is the TypeScript source.
        Written to ~/.pi/agent/extensions/<name>.ts
      '';
    };

    npmPackages = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = ''
        NPM packages to install for pi extensions.
        Each key is the package name, value is the version constraint.
        Written to ~/.pi/agent/npm/package.json and installed on activation.

        Example:
        {
          "pi-web-access" = "^0.10.7";
          "pi-opencode-provider" = "^0.7.3";
        }
      '';
    };

    themes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = ''
        Custom themes as attribute set.
        Each key is the theme name, value is a theme attribute set.
        Written to ~/.pi/agent/themes/<name>.json
      '';
    };

    pluginsSource = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the pi-plugins repository.
        Set to inputs.pi-plugins for the locked flake version,
        or an absolute local path (e.g., /home/user/src/pi-plugins) for development.
        When null, no plugins are copied from an external source.
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        List of plugin names to install from pluginsSource.
        Each name corresponds to a package in packages/<name>/src/index.ts
        within the pi-plugins repository.
        The plugin's extension is copied to ~/.pi/agent/extensions/<name>.ts
        and any matching skill in .pi/skills/<name>/ is copied to ~/.pi/agent/skills/.
      '';
    };
  };
}
