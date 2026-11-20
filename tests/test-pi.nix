# Pi coding agent option tests
# Validates option defaults and custom values
{pkgs, ...}: let
  inherit (pkgs) lib;
  piHomeManagerModuleText = builtins.readFile ../modules/home-manager/pi-coding-agent.nix;

  stubModules = [
    ../modules/common/options.nix
    ../modules/common/pi.nix
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

  piDefaultEval = lib.evalModules {
    modules = stubModules;
  };
  piDefaults = piDefaultEval.config.myConfig.pi;
  piOptions = piDefaultEval.options.myConfig.pi;

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
                  provider = "openai-compatible";
                  modelId = "qwen3.5";
                  apiKeyFile = "~/.config/opencode/secrets/provider-key";
                };
              };
              jevOnePasswordItem = "Opencode/Service Accounts/TestHost";
              prompts = {
                "explain" = "Explain this";
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
  piBifrostModelMetadataTest =
    pkgs.runCommand "test-pi-bifrost-model-metadata" {
      nativeBuildInputs = [pkgs.nodejs];
    } ''
      node --input-type=module <<'NODE'
      import assert from "node:assert/strict";
      import {mapBifrostModel} from "file://${../modules/home-manager/bifrost-model-metadata.mjs}";

      const largeCloudModel = mapBifrostModel({
        id: "opencode-go/deepseek-v4.1-flash",
        context_window: 1000000,
        max_output_tokens: 384000,
      });
      assert.equal(largeCloudModel.contextWindow, 1000000);
      assert.equal(largeCloudModel.maxTokens, 32000);

      const localModel = mapBifrostModel({
        id: "omlx/qwen3.8-27b",
        context_length: 128000,
        max_output_tokens: 30720,
      });
      assert.equal(localModel.contextWindow, 128000);
      assert.equal(localModel.maxTokens, 30720);

      const smallOutputModel = mapBifrostModel({
        id: "opencode-go/small-output",
        context_length: 64000,
        max_output_tokens: 4096,
      });
      assert.equal(smallOutputModel.contextWindow, 64000);
      assert.equal(smallOutputModel.maxTokens, 4096);

      const missingLimitsModel = mapBifrostModel({id: "bifrost/unknown"});
      assert.equal(missingLimitsModel.contextWindow, 128000);
      assert.equal(missingLimitsModel.maxTokens, 32000);
      NODE
      touch $out
    '';

  piAuthJsonInitializationTest =
    pkgs.runCommand "test-pi-auth-json-initialization"
    {}
    ''
      echo "=== Testing Pi auth.json initialization ==="

      ${
        if lib.hasInfix ''".pi/agent/auth.json"'' piHomeManagerModuleText
        then ''echo "  auth.json is declared as a Home Manager file: OK"''
        else throw "Pi auth.json must be declared through Home Manager"
      }

      if ${lib.boolToString (lib.hasInfix ''key = "!cat ~/$'' piHomeManagerModuleText)}; then
        echo "  auth.json uses the OpNix-managed secret file: OK"
      else
        echo "  auth.json does not use the OpNix-managed secret file"
        exit 1
      fi

      if ${lib.boolToString (!(lib.hasInfix "home.activation.piOpenCodeGoAuth" piHomeManagerModuleText))}; then
        echo "  auth.json activation job is removed: OK"
      else
        echo "  auth.json activation job is still present"
        exit 1
      fi

      touch $out
    '';

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
      if piDefaults.opencodeGoOnePasswordItem == ""
      then ''echo "  OpenCode Go credential default = off: OK"''
      else ''echo "  OpenCode Go credential should default to off!"; exit 1''
    }

    ${
      if piDefaults.jevOnePasswordItem == ""
      then ''echo "  Jev credential default = empty: OK"''
      else ''echo "  Jev credential should default to empty!"; exit 1''
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
      if !(builtins.hasAttr "skills" piOptions)
      then ''echo "  Pi skills are sourced from the shared repository, not inline options: OK"''
      else ''echo "  inline Pi skill content must not override the shared repository"; exit 1''
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
      if piCustom.models.custom-model.apiKeyFile == "~/.config/opencode/secrets/provider-key"
      then ''echo "  models.custom-model.apiKeyFile configured: OK"''
      else ''echo "  models.custom-model.apiKeyFile should be configured!"; exit 1''
    }

    ${
      if piCustom.jevOnePasswordItem == "Opencode/Service Accounts/TestHost"
      then ''echo "  Jev credential reference configured: OK"''
      else ''echo "  Jev credential reference should be configured!"; exit 1''
    }

    ${
      if piCustom.prompts ? explain
      then ''echo "  prompts.explain defined: OK"''
      else ''echo "  prompts.explain should be defined!"; exit 1''
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
