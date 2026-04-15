{
  config,
  osConfig,
  lib,
  pkgs,
  earthsong,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.sketchybar;
  t = earthsong.sketchybarTheme;

  # Helper to convert hex color to sketchybar format
  toSketchybarColor = hex: "0x" + (builtins.replaceStrings ["#"] [""] hex);

  # Generate colors.lua from the Earthsong theme
  colorsLua = pkgs.writeText "colors.lua" ''
    return {
      black = ${toSketchybarColor t.colors.black},
      white = ${toSketchybarColor t.colors.white},
      red = ${toSketchybarColor t.colors.red},
      green = ${toSketchybarColor t.colors.green},
      blue = ${toSketchybarColor t.colors.blue},
      yellow = ${toSketchybarColor t.colors.yellow},
      orange = ${toSketchybarColor t.colors.orange},
      magenta = ${toSketchybarColor t.colors.magenta},
      grey = ${toSketchybarColor t.colors.grey},
      transparent = 0x00000000,

      bar = {
        bg = ${toSketchybarColor t.colors.bar.bg},
        border = ${toSketchybarColor t.colors.bar.border},
      },
      popup = {
        bg = ${toSketchybarColor t.colors.popup.bg},
        border = ${toSketchybarColor t.colors.popup.border}
      },
      bg1 = ${toSketchybarColor t.colors.bg1},
      bg2 = ${toSketchybarColor t.colors.bg2},

      with_alpha = function(color, alpha)
        if alpha > 1.0 or alpha < 0.0 then return color end
        return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
      end,
    }
  '';

  # Generate settings.lua from the Earthsong theme
  settingsLua = pkgs.writeText "settings.lua" ''
    return {
      font = {
        text = "${t.font.text}",
        numbers = "${t.font.numbers}",
      },
      group_paddings = ${toString cfg.groupPadding},
    }
  '';

  # Bar configuration
  barLua = pkgs.writeText "bar.lua" ''
    local colors = require("colors")

    sbar.bar({
      height = ${toString cfg.height},
      color = colors.bar.bg,
      display = "all",
      topmost = "window",
      padding_right = ${toString cfg.padding},
      padding_left = ${toString cfg.padding},
    })
  '';

  # Default styles configuration
  defaultLua = pkgs.writeText "default.lua" ''
    local colors = require("colors")

    -- Default item settings
    sbar.default({
      updates = "when_shown",
      icon = {
        font = {
          family = "${t.font.text}",
          style = "Bold",
          size = 14.0
        },
        color = colors.white,
        padding_left = 8,
        padding_right = 8,
      },
      label = {
        font = {
          family = "${t.font.text}",
          style = "Semibold",
          size = 13.0
        },
        color = colors.white,
        padding_left = 8,
        padding_right = 8,
      },
      background = {
        height = 28,
        corner_radius = 6,
        border_width = 1,
        border_color = colors.bg2,
        color = colors.bg1,
        padding_left = 4,
        padding_right = 4,
      },
      popup = {
        background = {
          border_width = 1,
          corner_radius = 6,
          border_color = colors.popup.border,
          color = colors.popup.bg,
          padding_left = 8,
          padding_right = 8,
        },
        blur_radius = 25,
      },
      padding_left = 4,
      padding_right = 4,
    })
  '';

  # Icons configuration
  iconsLua = pkgs.writeText "icons.lua" ''
    return {
      apple = "",
      plus = "",
      gear = "",
      cpu = "",
      clipboard = "",

      switch = {
        on = "",
        off = "",
      },
      volume = {
        _100 = "",
        _66 = "",
        _33 = "",
        _10 = "",
        _0 = "",
      },
      battery = {
        _100 = "",
        _75 = "",
        _50 = "",
        _25 = "",
        _0 = "",
        charging = "",
      },
      wifi = {
        _0 = "",
        _1 = "",
        _2 = "",
        _3 = "",
      },
      error = "",
    }
  '';

  # Entry point: sketchybarrc requires all Lua modules and appends extraConfig
  sketchybarrc = pkgs.writeText "sketchybarrc" ''
    require("colors")
    require("settings")
    require("bar")
    require("default")
    require("icons")
    ${cfg.extraConfig}
  '';
in {
  config = mkIf (cfg.enable && osConfig.myConfig.isDarwin) {
    home.file = {
      # Entry point loaded by the launchd agent
      ".config/sketchybar/sketchybarrc".source = sketchybarrc;
      # Supporting Lua config files
      ".config/sketchybar/colors.lua".source = colorsLua;
      ".config/sketchybar/settings.lua".source = settingsLua;
      ".config/sketchybar/bar.lua".source = barLua;
      ".config/sketchybar/default.lua".source = defaultLua;
      ".config/sketchybar/icons.lua".source = iconsLua;
    };

    # Install required packages
    home.packages = with pkgs;
      [
        sketchybar
        sketchybar-app-font
      ]
      ++ lib.optionals cfg.useAerospaceIntegration [
        aerospace
        jankyborders
        nowplaying-cli
      ];

    # Create launchd service for sketchybar
    launchd.agents.sketchybar = {
      enable = true;
      config = {
        Label = "com.felixkratz.sketchybar";
        ProgramArguments = [
          "${pkgs.sketchybar}/bin/sketchybar"
          "--config"
          "${config.home.homeDirectory}/.config/sketchybar/sketchybarrc"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/sketchybar.log";
        StandardErrorPath = "/tmp/sketchybar.err.log";
      };
    };
  };
}
