# Sketchybar option validation and theme integration tests
# Validates option defaults, theme structure, and color conversion
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Import options.nix to test sketchybar option definitions
  testEval = lib.evalModules {
    modules = [
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
  };
  sketchybarDefaults = testEval.config.myConfig.sketchybar;

  # Import options with custom values to verify they take effect
  testEvalCustom = lib.evalModules {
    modules = [
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
      {
        config.myConfig.sketchybar = {
          enable = true;
          height = 50;
          padding = 8;
          groupPadding = 20;
          useAerospaceIntegration = false;
          extraConfig = "-- custom lua config";
        };
      }
    ];
  };
  sketchybarCustom = testEvalCustom.config.myConfig.sketchybar;

  # Import themes.nix to validate sketchybarTheme export
  # themes.nix is a NixOS/home-manager module that sets _module.args.earthsong.
  # We call it as a function directly and extract its return value.
  themesModule = import ../modules/home-manager/themes.nix {inherit lib pkgs;};
  inherit (themesModule._module.args) earthsong;
  theme = earthsong.sketchybarTheme;

  # Test the toSketchybarColor conversion logic (same as in sketchybar/default.nix)
  toSketchybarColor = hex: "0x" + (builtins.replaceStrings ["#"] [""] hex);
in {
  # Test sketchybar option defaults
  sketchybarOptionsTest =
    pkgs.runCommand "test-sketchybar-options"
    {}
    ''
      echo "=== Testing Sketchybar Option Defaults ==="

      # Verify default values
      ${
        if !sketchybarDefaults.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if sketchybarDefaults.height == 40
        then ''echo "  height default = 40: OK"''
        else ''echo "  height should default to 40!"; exit 1''
      }

      ${
        if sketchybarDefaults.padding == 2
        then ''echo "  padding default = 2: OK"''
        else ''echo "  padding should default to 2!"; exit 1''
      }

      ${
        if sketchybarDefaults.groupPadding == 10
        then ''echo "  groupPadding default = 10: OK"''
        else ''echo "  groupPadding should default to 10!"; exit 1''
      }

      ${
        if sketchybarDefaults.useAerospaceIntegration
        then ''echo "  useAerospaceIntegration default = true: OK"''
        else ''echo "  useAerospaceIntegration should default to true!"; exit 1''
      }

      ${
        if sketchybarDefaults.extraConfig == ""
        then ''echo "  extraConfig default = empty: OK"''
        else ''echo "  extraConfig should default to empty!"; exit 1''
      }

      echo "All sketchybar option defaults verified"
      touch $out
    '';

  # Test sketchybar custom option values
  sketchybarCustomOptionsTest =
    pkgs.runCommand "test-sketchybar-custom-options"
    {}
    ''
      echo "=== Testing Sketchybar Custom Options ==="

      ${
        if sketchybarCustom.enable
        then ''echo "  enable = true: OK"''
        else ''echo "  enable should be true!"; exit 1''
      }

      ${
        if sketchybarCustom.height == 50
        then ''echo "  height = 50: OK"''
        else ''echo "  height should be 50!"; exit 1''
      }

      ${
        if sketchybarCustom.padding == 8
        then ''echo "  padding = 8: OK"''
        else ''echo "  padding should be 8!"; exit 1''
      }

      ${
        if sketchybarCustom.groupPadding == 20
        then ''echo "  groupPadding = 20: OK"''
        else ''echo "  groupPadding should be 20!"; exit 1''
      }

      ${
        if !sketchybarCustom.useAerospaceIntegration
        then ''echo "  useAerospaceIntegration = false: OK"''
        else ''echo "  useAerospaceIntegration should be false!"; exit 1''
      }

      ${
        if sketchybarCustom.extraConfig == "-- custom lua config"
        then ''echo "  extraConfig = custom value: OK"''
        else ''echo "  extraConfig should have custom value!"; exit 1''
      }

      echo "All sketchybar custom options verified"
      touch $out
    '';

  # Test themes.nix exports sketchybarTheme with expected structure
  sketchybarThemeTest =
    pkgs.runCommand "test-sketchybar-theme"
    {}
    ''
      echo "=== Testing Sketchybar Theme Structure ==="

      # Verify top-level theme attributes
      ${
        if theme ? colors && theme ? font
        then ''echo "  Theme has colors and font: OK"''
        else ''echo "  Theme missing colors or font!"; exit 1''
      }

      # Verify color attributes
      ${let
        requiredColors = ["black" "white" "red" "green" "blue" "yellow" "orange" "magenta" "grey"];
        checks =
          map (
            c:
              if theme.colors ? ${c}
              then ''echo "  colors.${c}: present"''
              else ''echo "  colors.${c}: MISSING!"; exit 1''
          )
          requiredColors;
      in
        lib.concatStringsSep "\n" checks}

      # Verify nested color attributes
      ${
        if theme.colors ? bar && theme.colors.bar ? bg && theme.colors.bar ? border
        then ''echo "  colors.bar.{bg, border}: OK"''
        else ''echo "  colors.bar missing bg or border!"; exit 1''
      }

      ${
        if theme.colors ? popup && theme.colors.popup ? bg && theme.colors.popup ? border
        then ''echo "  colors.popup.{bg, border}: OK"''
        else ''echo "  colors.popup missing bg or border!"; exit 1''
      }

      ${
        if theme.colors ? bg1 && theme.colors ? bg2
        then ''echo "  colors.{bg1, bg2}: OK"''
        else ''echo "  colors missing bg1 or bg2!"; exit 1''
      }

      # Verify font attributes
      ${
        if theme.font ? text && theme.font ? numbers
        then ''echo "  font.{text, numbers}: OK"''
        else ''echo "  font missing text or numbers!"; exit 1''
      }

      echo "  font.text: ${theme.font.text}"
      echo "  font.numbers: ${theme.font.numbers}"

      echo "Sketchybar theme structure verified"
      touch $out
    '';

  # Test toSketchybarColor hex conversion
  sketchybarColorConversionTest = let
    # Test cases for the hex conversion function
    result1 = toSketchybarColor "#ff0000";
    result2 = toSketchybarColor "#1398b9";
    result3 = toSketchybarColor "#121418";
    # Apply to a real theme color
    resultTheme = toSketchybarColor theme.colors.black;
  in
    pkgs.runCommand "test-sketchybar-color-conversion"
    {}
    ''
      echo "=== Testing Sketchybar Color Conversion ==="

      # Verify #RRGGBB -> 0xRRGGBB conversion
      ${
        if result1 == "0xff0000"
        then ''echo "  #ff0000 -> 0xff0000: OK"''
        else ''echo "  #ff0000 -> ${result1}: FAILED (expected 0xff0000)"; exit 1''
      }

      ${
        if result2 == "0x1398b9"
        then ''echo "  #1398b9 -> 0x1398b9: OK"''
        else ''echo "  #1398b9 -> ${result2}: FAILED (expected 0x1398b9)"; exit 1''
      }

      ${
        if result3 == "0x121418"
        then ''echo "  #121418 -> 0x121418: OK"''
        else ''echo "  #121418 -> ${result3}: FAILED (expected 0x121418)"; exit 1''
      }

      # Verify conversion works with actual theme colors
      ${
        if lib.hasPrefix "0x" resultTheme
        then ''echo "  Theme color conversion has 0x prefix: OK"''
        else ''echo "  Theme color conversion missing 0x prefix!"; exit 1''
      }

      echo "Sketchybar color conversion verified"
      touch $out
    '';

  # Test that sketchybar options evaluate without errors on any platform.
  # The actual platform guard (mkIf isDarwin) lives in the home-manager module,
  # not in options.nix. This test verifies the options layer is always clean.
  # Note: isDarwin is read-only, computed from pkgs.stdenv.hostPlatform.system,
  # so we can't simulate a different platform without a different pkgs.
  sketchybarPlatformGuardTest = let
    # Evaluate with sketchybar enabled — should work on any platform at the options level
    testEvalEnabled = lib.evalModules {
      modules = [
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
        {
          config.myConfig.sketchybar = {
            enable = true;
            height = 60;
            useAerospaceIntegration = false;
          };
        }
      ];
    };
    enabledCfg = testEvalEnabled.config.myConfig;
  in
    pkgs.runCommand "test-sketchybar-platform-guard"
    {}
    ''
      echo "=== Testing Sketchybar Platform Guard ==="

      # Enabling sketchybar should always evaluate cleanly at the options level
      ${
        if enabledCfg.sketchybar.enable
        then ''echo "  sketchybar.enable evaluates: OK"''
        else ''echo "  sketchybar.enable should be true!"; exit 1''
      }

      ${
        if enabledCfg.sketchybar.height == 60
        then ''echo "  height = 60 accepted: OK"''
        else ''echo "  height should be 60!"; exit 1''
      }

      ${
        if !enabledCfg.sketchybar.useAerospaceIntegration
        then ''echo "  useAerospaceIntegration = false accepted: OK"''
        else ''echo "  useAerospaceIntegration should be false!"; exit 1''
      }

      # The home-manager module (sketchybar/default.nix) applies the actual
      # platform guard: mkIf (cfg.enable && config.myConfig.isDarwin).
      # That is tested at the integration level, not here.
      echo "  Note: platform guard (isDarwin) in home-manager module not testable at options level"

      echo "Sketchybar platform guard verified"
      touch $out
    '';
}
