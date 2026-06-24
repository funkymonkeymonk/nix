# Claude Code option tests
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

  claudeDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.claude-code;

  claudeCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.claude-code = {
              enable = true;
              includeCoAuthoredBy = true;
              mcpServers = {
                test-server = {
                  type = "local";
                  command = ["node" "server.js"];
                  enabled = true;
                };
              };
              agents = {
                "reviewer" = "Code review agent";
              };
              commands = {
                "explain" = "Explain this code";
              };
              hooks = {
                "pre-commit" = "Run tests";
              };
            };
          }
        ];
    }).config.myConfig.claude-code;
in {
  claudeCodeOptionsTest = pkgs.runCommand "test-claude-code-options" {} ''
    echo "=== Testing Claude Code Option Defaults ==="

    ${
      if !claudeDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if !claudeDefaults.includeCoAuthoredBy
      then ''echo "  includeCoAuthoredBy default = false: OK"''
      else ''echo "  includeCoAuthoredBy should default to false!"; exit 1''
    }

    ${
      if claudeDefaults.extraSettings == {}
      then ''echo "  extraSettings default = {}: OK"''
      else ''echo "  extraSettings should default to {}!"; exit 1''
    }

    ${
      if claudeDefaults.mcpServers == {}
      then ''echo "  mcpServers default = {}: OK"''
      else ''echo "  mcpServers should default to {}!"; exit 1''
    }

    ${
      if claudeDefaults.agents == {}
      then ''echo "  agents default = {}: OK"''
      else ''echo "  agents should default to {}!"; exit 1''
    }

    ${
      if claudeDefaults.commands == {}
      then ''echo "  commands default = {}: OK"''
      else ''echo "  commands should default to {}!"; exit 1''
    }

    ${
      if claudeDefaults.hooks == {}
      then ''echo "  hooks default = {}: OK"''
      else ''echo "  hooks should default to {}!"; exit 1''
    }

    echo "All Claude Code option defaults verified"
    touch $out
  '';

  claudeCodeCustomOptionsTest = pkgs.runCommand "test-claude-code-custom-options" {} ''
    echo "=== Testing Claude Code Custom Options ==="

    ${
      if claudeCustom.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if claudeCustom.includeCoAuthoredBy
      then ''echo "  includeCoAuthoredBy = true: OK"''
      else ''echo "  includeCoAuthoredBy should be true!"; exit 1''
    }

    ${
      if claudeCustom.mcpServers ? test-server
      then ''echo "  mcpServers.test-server defined: OK"''
      else ''echo "  mcpServers.test-server should be defined!"; exit 1''
    }

    ${
      if claudeCustom.agents ? reviewer
      then ''echo "  agents.reviewer defined: OK"''
      else ''echo "  agents.reviewer should be defined!"; exit 1''
    }

    ${
      if claudeCustom.commands ? explain
      then ''echo "  commands.explain defined: OK"''
      else ''echo "  commands.explain should be defined!"; exit 1''
    }

    ${
      if claudeCustom.hooks ? pre-commit
      then ''echo "  hooks.pre-commit defined: OK"''
      else ''echo "  hooks.pre-commit should be defined!"; exit 1''
    }

    echo "All Claude Code custom options verified"
    touch $out
  '';
}
