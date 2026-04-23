# Tests for NixOS module options
# Verifies typed attrset options accept expected value types
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Stubs for evaluating options.nix in isolation (no platform-specific modules)
  baseStubs = [
    ../modules/common/options.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
      config._module.args = {inherit pkgs;};
      config.myConfig.users = [
        {
          name = "testuser";
          email = "test@example.com";
          fullName = "Test User";
          isAdmin = true;
          sshIncludes = [];
        }
      ];
    }
  ];

  # Evaluate options.nix with attrsOf anything values for the typed options
  typedAttrsEval =
    (lib.evalModules {
      modules =
        baseStubs
        ++ [
          {
            config.myConfig.charm.mods.settings = {
              some_key = "value";
              nested = {key = 42;};
            };
            config.myConfig.claude-code.extraSettings = {
              theme = "dark";
              autoApprove = true;
            };
            config.myConfig.pi.settings = {
              model = "gpt-4o";
              maxTokens = 4096;
            };
            config.myConfig.pi.themes = {
              dark = {
                background = "#000000";
                foreground = "#ffffff";
              };
            };
          }
        ];
    })
    .config;
in {
  # Test: types.attrsOf types.anything options accept arbitrary attrsets
  # Verifies that mods.settings, claude-code.extraSettings, pi.settings, and
  # pi.themes accept nested attrset values without type errors.
  typedAttrsOptionsTest =
    pkgs.runCommand "test-typed-attrs-options"
    {}
    ''
      echo "=== Testing typed attrset options ==="

      ${
        if typedAttrsEval.myConfig.charm.mods.settings.some_key == "value"
        then ''echo "  mods.settings accepts string value: OK"''
        else ''
          echo "  FAIL: mods.settings value mismatch"
          exit 1
        ''
      }

      ${
        if typedAttrsEval.myConfig.claude-code.extraSettings.theme == "dark"
        then ''echo "  claude-code.extraSettings accepts string value: OK"''
        else ''
          echo "  FAIL: claude-code.extraSettings value mismatch"
          exit 1
        ''
      }

      ${
        if typedAttrsEval.myConfig.pi.settings.model == "gpt-4o"
        then ''echo "  pi.settings accepts string value: OK"''
        else ''
          echo "  FAIL: pi.settings value mismatch"
          exit 1
        ''
      }

      ${
        if typedAttrsEval.myConfig.pi.themes.dark.background == "#000000"
        then ''echo "  pi.themes accepts nested attrset: OK"''
        else ''
          echo "  FAIL: pi.themes value mismatch"
          exit 1
        ''
      }

      echo "All typed attrset option tests passed"
      touch $out
    '';
}
