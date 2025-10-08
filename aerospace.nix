{
  config,
  pkgs,
  ...
}: {
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
        outer.left = 0;
        outer.bottom = 0;
        outer.top = 0;
        outer.right = 0;
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

        shift-ctrl-alt-1 = "move-node-to-workspace 1";
        shift-ctrl-alt-2 = "move-node-to-workspace 2";
        shift-ctrl-alt-3 = "move-node-to-workspace 3";
        shift-ctrl-alt-4 = "workspace 1";
        shift-ctrl-alt-5 = "workspace 2";
        shift-ctrl-alt-6 = "workspace 3";
      };

      on-window-detected = [
        {
	  "if" = {
	    app-id = "com.hnc.Discord";
	  };
	  run = ["move-node-to-workspace 1"];
	}
	{
	  "if" = {
	    app-id = "com.readdle.smartemail-Mac";
	  };
	  run = ["move-node-to-workspace 1"];
	}
	{
	  "if" = {
	    app-id = "com.deezer.deezer-desktop";
	  };
	  run = ["move-node-to-workspace 2"];
	}
	{
	  "if" = {
	    app-id = "com.electron.logseq";
	  };
	  run = ["move-node-to-workspace 2"];
	}
      ];
      workspace-to-monitor-force-assignment = {
        "1" = [
	  "1"
	  "3"
	];
	"2" = [
	  "3"
	  "1"
	];
      };
    };
  };
}
