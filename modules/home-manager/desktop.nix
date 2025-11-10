{pkgs, ...}: {
  home.packages = [
    (pkgs.writeShellScriptBin "dropdown-terminal-toggle" ''
      #!/bin/bash

      # Dropdown terminal toggle script for AeroSpace window manager
      # Toggles a floating Alacritty terminal window between visible and hidden workspaces

      CURRENT_WS=$(aerospace list-workspaces --focused --format "%{workspace}")
      WIN_EXISTS=$(aerospace list-windows --all --json | jq ".[] | select(.\"app-name\" == \"alacritty\" and .\"window-title\" == \"dropdown-terminal\") | .\"window-id\"" | head -1)

      if [ -n "$WIN_EXISTS" ]; then
        if [ "$CURRENT_WS" = "dropdown-hidden" ]; then
          aerospace move-node-to-workspace --focus-follows-window 1.Main
        else
          aerospace move-node-to-workspace --focus-follows-window dropdown-hidden
        fi
      else
        alacritty --class dropdown --title "dropdown-terminal" &
      fi
    '')
  ];

  services.aerospace = {
    enable = true;
    package = pkgs.unstable.aerospace;

    settings = {
      after-startup-command = [
        "layout tiles"
      ];

      gaps = {
        inner.horizontal = 0;
        inner.vertical = 0;
        outer = {
          left = 0;
          bottom = 0;
          top = 0;
          right = 0;
        };
      };

      mode.main.binding = {
        shift-ctrl-alt-h = "focus left";
        shift-ctrl-alt-j = "focus down";
        shift-ctrl-alt-k = "focus up";
        shift-ctrl-alt-l = "focus right";

        shift-ctrl-alt-y = "swap --swap-focus left";
        shift-ctrl-alt-u = "swap --swap-focus down";
        shift-ctrl-alt-i = "swap --swap-focus up";
        shift-ctrl-alt-o = "swap --swap-focus right";

        shift-ctrl-alt-n = "move left";
        shift-ctrl-alt-m = "move down";
        shift-ctrl-alt-comma = "move up";
        shift-ctrl-alt-period = "move right";

        shift-ctrl-alt-left = "join-with left";
        shift-ctrl-alt-down = "join-with down";
        shift-ctrl-alt-up = "join-with up";
        shift-ctrl-alt-right = "join-with right";

        shift-ctrl-alt-p = "resize smart +200";
        shift-ctrl-alt-quote = "balance-sizes";
        shift-ctrl-alt-slash = "resize smart -200";

        shift-ctrl-alt-4 = "move-node-to-workspace --wrap-around prev";
        shift-ctrl-alt-5 = "workspace --wrap-around prev";
        shift-ctrl-alt-6 = "workspace --wrap-around next";
        shift-ctrl-alt-equal = "move-node-to-workspace --wrap-around next";

        shift-ctrl-alt-t = "exec-and-forget dropdown-terminal-toggle";
      };

      on-window-detected = [
        {
          "if" = {
            app-id = "com.hnc.Discord";
          };
          run = ["move-node-to-workspace 2.Comms"];
        }
        {
          "if" = {
            app-id = "com.readdle.smartemail-Mac";
          };
          run = ["move-node-to-workspace 2.Comms"];
        }
        {
          "if" = {
            app-id = "com.deezer.deezer-desktop";
          };
          run = ["move-node-to-workspace 3.Dash"];
        }
        {
          "if" = {
            app-id = "com.electron.logseq";
          };
          run = ["move-node-to-workspace 3.Dash"];
        }
        {
          "if" = {
            app-name-regex-substring = "alacritty";
            window-title-regex-substring = "dropdown-terminal";
          };
          run = ["layout floating"];
        }
      ];
      workspace-to-monitor-force-assignment = {
        "1.Main" = [
          "Main"
        ];
        "2.Comms" = [
          "1"
          "3"
        ];
        "3.Dash" = [
          "3"
          "1"
        ];
        "4.Distracted" = [
          "Main"
        ];
      };
    };
  };
}
