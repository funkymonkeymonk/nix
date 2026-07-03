# Home Manager module for pi-coding-agent
# Manages pi configuration files in ~/.pi/agent/
{
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.pi;
  skillsCfg = osConfig.myConfig.skills or {};
  hmLib = import ./lib.nix {inherit lib;};

  # Filter models that have 1Password items configured
  modelsWithSecrets = lib.filterAttrs (_name: model: model.onePasswordItem != "") cfg.models;

  # Build opnix secrets configuration
  opnixSecrets = hmLib.mkOpnixSecrets "pi" osConfig.myConfig.onepassword.defaultVault (
    lib.mapAttrs (name: model: {
      inherit (model) onePasswordItem;
      secretPath = ".pi/agent/secrets/${name}-apikey";
    })
    modelsWithSecrets
  );

  # Build models config for pi v0.75.4+ schema
  # Maps our per-model options to the nested provider+models format pi expects
  # When modelId is empty, treats this as a built-in provider override
  # (only apiKey is emitted, preserving built-in models)
  modelsConfig = lib.mapAttrs (_name: model:
    lib.filterAttrs (_k: v: v != null && v != "" && v != []) {
      baseUrl =
        if model.baseUrl != ""
        then model.baseUrl
        else null;
      api =
        if model.modelId != ""
        then "openai-completions"
        else null;
      apiKey =
        if model.onePasswordItem != ""
        then "{file:~/.pi/agent/secrets/${_name}-apikey}"
        else if model.apiKey != ""
        then model.apiKey
        else if model.modelId != ""
        then "dummy"
        else null;
      models =
        if model.modelId != ""
        then let
          baseModel =
            {
              id = model.modelId;
              name = model.name;
            }
            // lib.optionalAttrs model.reasoning {
              reasoning = true;
            }
            // lib.optionalAttrs (model.maxTokens != null) {
              maxTokens = model.maxTokens;
            };
        in [baseModel]
        else null;
      compat =
        if model.modelId == ""
        then {}
        else null;
    })
  cfg.models;

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

  # Combine user AGENTS.md with auto-loaded skills
  agentsMdWithAutoLoad = let
    base =
      if cfg.agentsMd != ""
      then cfg.agentsMd
      else "";
    autoSection =
      if hasAutoLoadSkills
      then "\n\n# Auto-Loaded Skills\n\n${autoLoadContent}"
      else "";
  in
    base + autoSection;

  # Build package references for settings.json from npmPackages
  # Format: npm:package-name@version (e.g., npm:pi-web-access@^0.10.7)
  npmPackageRefs = lib.mapAttrsToList (name: version: "npm:${name}@${version}") cfg.npmPackages;

  # Merge npm packages into settings.json so Pi actually loads them
  settingsWithPackages =
    if cfg.npmPackages != {}
    then cfg.settings // {packages = (cfg.settings.packages or []) ++ npmPackageRefs;}
    else cfg.settings;

  # Core configuration files
  coreFiles = {
    ".pi/agent/settings.json" = mkIf (settingsWithPackages != {}) {
      text = builtins.toJSON settingsWithPackages;
      force = true;
    };
    ".pi/agent/AGENTS.md" = mkIf (agentsMdWithAutoLoad != "") {
      text = agentsMdWithAutoLoad;
    };
    ".pi/agent/SYSTEM.md" = mkIf (cfg.systemMd != "") {
      text = cfg.systemMd;
    };
    ".pi/agent/keybindings.json" = mkIf (cfg.keybindings != {}) {
      text = builtins.toJSON cfg.keybindings;
    };
    ".pi/agent/models.json" = mkIf (cfg.models != {}) {
      text = builtins.toJSON {providers = modelsConfig;};
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

  # NPM package.json for pi extensions
  npmPackageJson = lib.optionalString (cfg.npmPackages != {}) (builtins.toJSON {
    name = "pi-extensions";
    private = true;
    dependencies = cfg.npmPackages;
  });

  npmFiles = lib.optionalAttrs (cfg.npmPackages != {}) {
    ".pi/agent/npm/package.json" = {
      text = npmPackageJson;
      force = true;
    };
  };

  # Bifrost model discovery extension
  # Auto-discovers available models from bifrost's /v1/models endpoint
  # and registers them dynamically so pi can use any model bifrost serves
  bifrostDiscoveryFiles = let
    bifrostModels =
      lib.filterAttrs (
        _name: model:
          model.baseUrl != "" && lib.hasInfix "bifrost" model.baseUrl
      )
      cfg.models;
    hasBifrost = bifrostModels != {};
    firstBifrost = lib.head (lib.attrValues bifrostModels);
    bifrostBase = lib.removeSuffix "/" firstBifrost.baseUrl;
  in
    lib.optionalAttrs hasBifrost {
      ".pi/agent/extensions/bifrost-discovery/package.json" = {
        text = builtins.toJSON {
          name = "bifrost-discovery";
          pi = {
            extensions = ["./index.ts"];
          };
        };
      };
      ".pi/agent/extensions/bifrost-discovery/index.ts" = {
        text = ''
          export default async function (pi: any) {
            try {
              const response = await fetch("${bifrostBase}/models");
              if (!response.ok) {
                console.error(`[bifrost-discovery] HTTP ''${response.status}`);
                return;
              }
              const payload = await response.json();
              if (!Array.isArray(payload.data)) {
                console.error("[bifrost-discovery] Unexpected response format");
                return;
              }
              const models = payload.data.map((m: any) => ({
                id: m.id,
                name: m.name || m.id,
                reasoning: /thinking|reasoning/i.test(m.id),
                input: ["text"],
                cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                contextWindow: 128000,
              }));
              pi.registerProvider("bifrost", {
                baseUrl: "${bifrostBase}",
                apiKey: "dummy",
                api: "openai-completions",
                models,
              });
              console.log(`[bifrost-discovery] Registered ''${models.length} models`);
            } catch (err) {
              console.error("[bifrost-discovery] Discovery failed:", err);
            }
          }
        '';
      };
    };

  # pi-plugins external source files
  # When pluginsSource is set, copy selected extensions and all skills from that repo
  pluginSourceFiles = let
    src = cfg.pluginsSource;
    names = cfg.plugins;
    hasSource = src != null && names != [];
    # Build extension file entries from pi-plugins packages/
    # Each plugin is a directory (like bifrost-discovery) so relative imports
    # (e.g. ./commands.js, ./tools.js) resolve correctly at runtime.
    extEntries = lib.concatLists (map (
        name: let
          extPath = src + "/packages/${name}/src";
        in
          lib.optional (builtins.pathExists (extPath + "/index.ts")) {
            name = ".pi/agent/extensions/${name}";
            value = {
              source = extPath;
              recursive = true;
            };
          }
      )
      names);
    # Copy all skills from pi-plugins .pi/skills/ (skills are tightly coupled to extensions)
    skillsDir = src + "/.pi/skills";
    skillNames =
      if builtins.pathExists skillsDir
      then lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir skillsDir))
      else [];
    skillEntries =
      map (name: {
        name = ".pi/agent/skills/${name}";
        value = {
          source = skillsDir + "/${name}";
          recursive = true;
        };
      })
      skillNames;
  in
    lib.optionalAttrs hasSource (lib.listToAttrs (extEntries ++ skillEntries));

  # Model-stack skill (directory with scripts)
  modelStackPath = ../../skills/model-stack;
  modelStackFiles = lib.optionalAttrs (builtins.pathExists modelStackPath) {
    ".pi/agent/skills/model-stack" = {
      source = modelStackPath;
      recursive = true;
    };
  };

  # All files merged together
  allFiles = coreFiles // promptFiles // skillFiles // extensionFiles // themeFiles // npmFiles // bifrostDiscoveryFiles // pluginSourceFiles // modelStackFiles;

  # pi-dev: run pi with local plugin overrides (no special shell needed)
  pi-dev-script = pkgs.writeShellScriptBin "pi-dev" ''
    set -euo pipefail

    PLUGINS_DIR=''${PI_PLUGINS_DIR:-$HOME/src/funkymonkeymonk/pi-plugins}
    AGENT_DIR=''${PI_DEV_AGENT_DIR:-$HOME/.pi/agent-dev}
    SYSTEM_AGENT="$HOME/.pi/agent"

    if [[ ! -d "$PLUGINS_DIR" ]]; then
      echo "Error: PI_PLUGINS_DIR not found: $PLUGINS_DIR"
      echo "Clone pi-plugins and set PI_PLUGINS_DIR, or run from the repo:"
      echo "  PI_PLUGINS_DIR=/path/to/pi-plugins pi-dev"
      exit 1
    fi

    echo "Merging pi config with plugins from $PLUGINS_DIR"
    mkdir -p "$AGENT_DIR"

    link_dir() {
      local src="$1"
      local dst="$2"
      mkdir -p "$dst"
      if [[ -d "$src" ]]; then
        for item in "$src"/*; do
          [[ -e "$item" ]] || continue
          local name=$(basename "$item")
          [[ -e "$dst/$name" ]] && continue
          ln -sf "$item" "$dst/$name"
        done
      fi
    }

    # Core config files
    for f in settings.json models.json keybindings.json SYSTEM.md APPEND_SYSTEM.md; do
      if [[ -f "$SYSTEM_AGENT/$f" && ! -f "$AGENT_DIR/$f" ]]; then
        cp "$SYSTEM_AGENT/$f" "$AGENT_DIR/$f"
      fi
    done

    # Merge directories
    for dir in skills prompts themes sessions; do
      link_dir "$SYSTEM_AGENT/$dir" "$AGENT_DIR/$dir"
    done

    # Link repo skills
    if [[ -d "$PLUGINS_DIR/.pi/skills" ]]; then
      mkdir -p "$AGENT_DIR/skills"
      for skill in "$PLUGINS_DIR/.pi/skills"/*; do
        [[ -d "$skill" ]] || continue
        name=$(basename "$skill")
        dst="$AGENT_DIR/skills/$name"
        [[ -e "$dst" ]] && continue
        ln -sf "$skill" "$dst"
        echo "  + skill $name"
      done
    fi

    # Link repo plugins
    mkdir -p "$AGENT_DIR/extensions"
    link_dir "$SYSTEM_AGENT/extensions" "$AGENT_DIR/extensions"

    for ext in "$PLUGINS_DIR"/packages/*/src/index.ts; do
      [[ -f "$ext" ]] || continue
      name=$(basename "$(dirname "$(dirname "$ext")")")
      dst="$AGENT_DIR/extensions/$name"
      mkdir -p "$dst"
      ln -sf "$ext" "$dst/index.ts"
      echo "  + plugin $name"
    done

    # NPM packages
    link_dir "$SYSTEM_AGENT/npm" "$AGENT_DIR/npm"
    link_dir "$SYSTEM_AGENT/git" "$AGENT_DIR/git"

    echo "Launching pi with merged config: $AGENT_DIR"
    export PI_CODING_AGENT_DIR="$AGENT_DIR"
    exec pi "$@"
  '';
in {
  config = mkIf cfg.enable {
    # All pi configuration files
    home.file = allFiles;

    # pi-dev script for testing local plugin changes
    home.packages = [pi-dev-script] ++ lib.optional (cfg.npmPackages != {}) pkgs.nodejs;

    # Run npm install when npm packages change
    home.activation.piNpmInstall = mkIf (cfg.npmPackages != {}) (lib.hm.dag.entryAfter ["writeBoundary"] ''
      npm_dir="$HOME/.pi/agent/npm"
      stamp_file="$npm_dir/.nix-package-json-target"
      current_target=$(readlink "$npm_dir/package.json" 2>/dev/null || echo "")

      if [ ! -f "$stamp_file" ] || [ "$(cat "$stamp_file" 2>/dev/null)" != "$current_target" ]; then
        $DRY_RUN_CMD mkdir -p "$npm_dir"
        $DRY_RUN_CMD cd "$npm_dir" && ${pkgs.nodejs}/bin/npm install
        $DRY_RUN_CMD echo "$current_target" > "$stamp_file"
      fi
    '');

    # Configure opnix secrets for models with 1Password items
    programs.onepassword-secrets = mkIf (modelsWithSecrets != {} && osConfig.myConfig.onepassword.enable) {
      enable = true;
      secrets = opnixSecrets;
    };
  };
}
