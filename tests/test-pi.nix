# Pi coding agent option tests
# Validates option defaults and custom values
{pkgs, ...}: let
  inherit (pkgs) lib;

  stubModules = [
    ../modules/common/options.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  piDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.pi;

  piCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.pi = {
              enable = true;
              settings = {
                theme = "dark";
                editor = "helix";
              };
              agentsMd = "# Global agent instructions";
              systemMd = "Custom system prompt";
              keybindings = {
                "acceptSuggestion" = "Tab";
              };
              models = {
                "custom-model" = {
                  name = "Custom";
                  provider = "ollama";
                  modelId = "qwen3.5";
                };
              };
              prompts = {
                "explain" = "Explain this";
              };
              skills = {
                "nix" = "Nix skill content";
              };
              extensions = {
                "my-ext" = "console.log('hello')";
              };
              npmPackages = {
                "pi-web-access" = "^0.10.7";
              };
              themes = {
                "custom" = {
                  background = "#000000";
                  foreground = "#ffffff";
                };
              };
            };
          }
        ];
    }).config.myConfig.pi;
in {
  piOptionsTest = pkgs.runCommand "test-pi-options" {} ''
    echo "=== Testing Pi Option Defaults ==="

    ${
      if !piDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if piDefaults.settings == {}
      then ''echo "  settings default = {}: OK"''
      else ''echo "  settings should default to {}!"; exit 1''
    }

    ${
      if piDefaults.agentsMd == ""
      then ''echo "  agentsMd default = empty: OK"''
      else ''echo "  agentsMd should default to empty!"; exit 1''
    }

    ${
      if piDefaults.systemMd == ""
      then ''echo "  systemMd default = empty: OK"''
      else ''echo "  systemMd should default to empty!"; exit 1''
    }

    ${
      if piDefaults.keybindings == {}
      then ''echo "  keybindings default = {}: OK"''
      else ''echo "  keybindings should default to {}!"; exit 1''
    }

    ${
      if piDefaults.models == {}
      then ''echo "  models default = {}: OK"''
      else ''echo "  models should default to {}!"; exit 1''
    }

    ${
      if piDefaults.prompts == {}
      then ''echo "  prompts default = {}: OK"''
      else ''echo "  prompts should default to {}!"; exit 1''
    }

    ${
      if piDefaults.skills == {}
      then ''echo "  skills default = {}: OK"''
      else ''echo "  skills should default to {}!"; exit 1''
    }

    ${
      if piDefaults.extensions == {}
      then ''echo "  extensions default = {}: OK"''
      else ''echo "  extensions should default to {}!"; exit 1''
    }

    ${
      if piDefaults.npmPackages == {}
      then ''echo "  npmPackages default = {}: OK"''
      else ''echo "  npmPackages should default to {}!"; exit 1''
    }

    ${
      if piDefaults.themes == {}
      then ''echo "  themes default = {}: OK"''
      else ''echo "  themes should default to {}!"; exit 1''
    }

    ${
      if piDefaults.pluginsSource == null
      then ''echo "  pluginsSource default = null: OK"''
      else ''echo "  pluginsSource should default to null!"; exit 1''
    }

    ${
      if piDefaults.plugins == []
      then ''echo "  plugins default = []: OK"''
      else ''echo "  plugins should default to []!"; exit 1''
    }

    echo "All Pi option defaults verified"
    touch $out
  '';

  piCustomOptionsTest = pkgs.runCommand "test-pi-custom-options" {} ''
    echo "=== Testing Pi Custom Options ==="

    ${
      if piCustom.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if piCustom.settings.theme == "dark"
      then ''echo "  settings.theme = dark: OK"''
      else ''echo "  settings.theme should be dark!"; exit 1''
    }

    ${
      if piCustom.settings.editor == "helix"
      then ''echo "  settings.editor = helix: OK"''
      else ''echo "  settings.editor should be helix!"; exit 1''
    }

    ${
      if piCustom.agentsMd == "# Global agent instructions"
      then ''echo "  agentsMd custom value: OK"''
      else ''echo "  agentsMd should be '# Global agent instructions'!"; exit 1''
    }

    ${
      if piCustom.systemMd == "Custom system prompt"
      then ''echo "  systemMd custom value: OK"''
      else ''echo "  systemMd should be 'Custom system prompt'!"; exit 1''
    }

    ${
      if piCustom.keybindings.acceptSuggestion == "Tab"
      then ''echo "  keybindings.acceptSuggestion = Tab: OK"''
      else ''echo "  keybindings.acceptSuggestion should be Tab!"; exit 1''
    }

    ${
      if piCustom.models ? custom-model
      then ''echo "  models.custom-model defined: OK"''
      else ''echo "  models.custom-model should be defined!"; exit 1''
    }

    ${
      if piCustom.prompts ? explain
      then ''echo "  prompts.explain defined: OK"''
      else ''echo "  prompts.explain should be defined!"; exit 1''
    }

    ${
      if piCustom.skills ? nix
      then ''echo "  skills.nix defined: OK"''
      else ''echo "  skills.nix should be defined!"; exit 1''
    }

    ${
      if piCustom.extensions ? my-ext
      then ''echo "  extensions.my-ext defined: OK"''
      else ''echo "  extensions.my-ext should be defined!"; exit 1''
    }

    ${
      if piCustom.npmPackages ? pi-web-access
      then ''echo "  npmPackages.pi-web-access defined: OK"''
      else ''echo "  npmPackages.pi-web-access should be defined!"; exit 1''
    }

    ${
      if piCustom.themes ? custom
      then ''echo "  themes.custom defined: OK"''
      else ''echo "  themes.custom should be defined!"; exit 1''
    }

    echo "All Pi custom options verified"
    touch $out
  '';
}
