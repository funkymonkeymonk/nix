{pkgs, ...}: {
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
        # All possible keys:
        # - Letters.        a, b, c, ..., z
        # - Numbers.        0, 1, 2, ..., 9
        # - Keypad numbers. keypad0, keypad1, keypad2, ..., keypad9
        # - F-keys.         f1, f2, ..., f20
        # - Special keys.   minus, equal, period, comma, slash, backslash, quote, semicolon,
        #                   backtick, leftSquareBracket, rightSquareBracket, space, enter, esc,
        #                   backspace, tab, pageUp, pageDown, home, end, forwardDelete,
        #                   sectionSign (ISO keyboards only, european keyboards only)
        # - Keypad special. keypadClear, keypadDecimalMark, keypadDivide, keypadEnter, keypadEqual,
        #                   keypadMinus, keypadMultiply, keypadPlus
        # - Arrows.         left, down, up, right
        # All possible modifiers: cmd, alt, ctrl, shift

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

        #shift-ctrl-alt-pageUp = "resize smart +200";
        #shift-ctrl-alt-pageDown = "resize smart +200";

        #shift-ctrl-alt-semicolon = "workspace";
        shift-ctrl-alt-4 = "move-node-to-workspace --wrap-around prev";
        shift-ctrl-alt-5 = "workspace --wrap-around prev";
        shift-ctrl-alt-6 = "workspace --wrap-around next";
        shift-ctrl-alt-equal = "move-node-to-workspace --wrap-around next";

        # Drop-down terminal toggle
        cmd-alt-space = "exec-and-forget dropdown_terminal";
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
            app-name = "Alacritty";
          };
          run = [
            "layout floating"
            "move-node-to-workspace 4.Distracted"
            "resize smart 100% 35%"
          ];
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
