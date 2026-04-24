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
  vwCfg = cfg.vivaldiWorkspaces;
  t = earthsong.sketchybarTheme;

  # Lua interpreter bundled with sbarlua
  lua = pkgs.sbarlua.luaModule;

  # Helper to convert hex color to sketchybar format (0xAARRGGBB)
  toSketchybarColor = hex: "0xff" + (builtins.replaceStrings ["#"] [""] hex);

  # Vivaldi workspaces helper script (shell), written to the Nix store.
  # Pulls jq and sketchybar from PATH at runtime — the parent sketchybar
  # launchd agent sets PATH to include pkgs.sketchybar, and we extend it
  # below when the option is enabled.
  vivaldiWorkspacesScript = pkgs.writeShellApplication {
    name = "sketchybar-vivaldi-workspaces";
    runtimeInputs = [pkgs.jq pkgs.sketchybar];
    # Disable shellcheck SC2016 (intentional single-quoted AppleScript)
    # and SC2155 (declare+assign in single line are fine for our use).
    checkPhase = "";
    text = builtins.readFile ./scripts/vivaldi-workspaces.sh;
  };

  # Template the Lua item by substituting @VW_POSITION@, @VW_ICON@, and
  # @VW_SCRIPT@ with the option values and Nix-store script path.
  vivaldiWorkspacesLua = pkgs.runCommand "vivaldi_workspaces.lua" {} ''
    substitute ${./items/vivaldi_workspaces.lua} $out \
      --replace-quiet '@VW_POSITION@' '${vwCfg.position}' \
      --replace-quiet '@VW_ICON@' '${vwCfg.iconText}' \
      --replace-quiet '@VW_SCRIPT@' '${vivaldiWorkspacesScript}/bin/sketchybar-vivaldi-workspaces'
  '';

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
      position = "${cfg.position}",
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
        height = 44,
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

  # Entry point: shell script that runs the Lua config via sbarlua
  # sketchybar executes this as a script (fork_exec), so it needs a shebang
  # and the executable bit. LUA_CPATH must include sbarlua's sketchybar.so.
  # LUA_PATH includes $CONFIG_DIR and $CONFIG_DIR/items so nested requires
  # (e.g. require("items.vivaldi_workspaces")) resolve reliably.
  sketchybarrc = pkgs.writeText "sketchybarrc" ''
    #!/bin/sh
    export LUA_CPATH="${pkgs.sbarlua}/lib/lua/5.5/?.so;;"
    export LUA_PATH="$CONFIG_DIR/?.lua;$CONFIG_DIR/?/init.lua;;"
    exec ${lua}/bin/lua "$CONFIG_DIR/init.lua"
  '';

  # Main Lua entry point (loaded by sketchybarrc shell script)
  initLua = pkgs.writeText "init.lua" ''
    sbar = require("sketchybar")
    require("colors")
    require("settings")
    require("bar")
    require("default")
    require("icons")
    ${lib.optionalString vwCfg.enable ''require("items.vivaldi_workspaces")''}
    ${cfg.extraConfig}
  '';

  # Bundle all Lua files into one store directory so sketchybar's CONFIG_DIR
  # resolves require() calls correctly (each pkgs.writeText produces a separate
  # store path, so require("colors") would fail to find colors.lua).
  configDir = pkgs.runCommand "sketchybar-config" {} ''
    mkdir -p $out/items
    cp ${colorsLua}    $out/colors.lua
    cp ${settingsLua}  $out/settings.lua
    cp ${barLua}       $out/bar.lua
    cp ${defaultLua}   $out/default.lua
    cp ${iconsLua}     $out/icons.lua
    cp ${initLua}      $out/init.lua
    cp ${sketchybarrc} $out/sketchybarrc
    chmod +x $out/sketchybarrc
    ${lib.optionalString vwCfg.enable ''
      cp ${vivaldiWorkspacesLua} $out/items/vivaldi_workspaces.lua
    ''}
  '';
in {
  config = mkIf (cfg.enable && osConfig.myConfig.isDarwin) {
    home.file = {
      # Symlink the whole config directory so all files share one store path
      ".config/sketchybar".source = configDir;
    };

    # Install required packages
    home.packages =
      [
        pkgs.sketchybar
        pkgs.sketchybar-app-font
        pkgs.sbarlua
        lua
      ]
      ++ lib.optionals cfg.useAerospaceIntegration [
        pkgs.aerospace
        pkgs.jankyborders
        pkgs.nowplaying-cli
      ]
      ++ lib.optionals vwCfg.enable [
        pkgs.jq
        vivaldiWorkspacesScript
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
        EnvironmentVariables = {
          # Include jq and the Vivaldi helper script directory on PATH when
          # the option is enabled, so the click scripts can find them.
          PATH = lib.concatStringsSep ":" (
            [
              "${pkgs.sketchybar}/bin"
            ]
            ++ lib.optionals vwCfg.enable [
              "${pkgs.jq}/bin"
              "${vivaldiWorkspacesScript}/bin"
            ]
            ++ [
              "/usr/local/bin"
              "/usr/bin"
              "/bin"
              "/usr/sbin"
              "/sbin"
            ]
          );
        };
      };
    };
  };
}
