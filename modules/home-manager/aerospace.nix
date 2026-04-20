{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig;

  # Script: summon an app to the focused workspace, dock it to the long edge
  # (left on landscape monitors, top on portrait), and size it to 1/3 of that
  # dimension. All tree manipulation uses --window-id, so focus never moves
  # (no visible flashing). Multi-monitor aware via the focused monitor's name
  # matched against system_profiler display data.
  aerospace-summon = pkgs.writeShellScriptBin "aerospace-summon" ''
    set -euo pipefail

    AS=/run/current-system/sw/bin/aerospace
    JQ=${pkgs.jq}/bin/jq
    SP=/usr/sbin/system_profiler

    BUNDLE_ID="''${1:-}"
    if [ -z "$BUNDLE_ID" ]; then
      echo "usage: aerospace-summon <bundle-id>" >&2
      exit 2
    fi

    # Target window (first match for this bundle id)
    WID=$("$AS" list-windows --all --json --format '%{window-id} %{app-bundle-id}' \
      | "$JQ" -r --arg b "$BUNDLE_ID" \
          'map(select(."app-bundle-id" == $b)) | .[0]."window-id" // empty')

    if [ -z "$WID" ]; then
      echo "aerospace-summon: no window for $BUNDLE_ID" >&2
      exit 1
    fi

    # Focused workspace
    WS=$("$AS" list-workspaces --focused --format '%{workspace}')

    # Focused monitor name
    MON_NAME=$("$AS" list-monitors --focused --format '%{monitor-name}')

    # Resolve monitor pixel dimensions from system_profiler by display name.
    # Falls back to 1920x1080 if the name isn't found (shouldn't happen).
    read -r MON_W MON_H < <("$SP" SPDisplaysDataType -json 2>/dev/null \
      | "$JQ" -r --arg n "$MON_NAME" '
          [.SPDisplaysDataType[]?.spdisplays_ndrvs[]?
           | select(._name == $n)
           | ._spdisplays_pixels]
          | .[0] // "1920 x 1080"' \
      | ${pkgs.gnused}/bin/sed -E 's/ x / /')

    # Pull window into current workspace (silent: no focus change)
    "$AS" move-node-to-workspace --window-id "$WID" "$WS"

    # Walk the window to the correct edge of the tree. `move` with --window-id
    # manipulates the tree without moving focus. No-op at the edge.
    if [ "$MON_W" -ge "$MON_H" ]; then
      DIR=left
      DIM=width
      SIZE=$((MON_W / 3))
    else
      DIR=up
      DIM=height
      SIZE=$((MON_H / 3))
    fi

    for _ in $(${pkgs.coreutils}/bin/seq 1 10); do
      "$AS" move "$DIR" --window-id "$WID" 2>/dev/null || true
    done

    "$AS" resize "$DIM" "$SIZE" --window-id "$WID" 2>/dev/null || true
  '';
in {
  environment.systemPackages = [aerospace-summon];

  services.aerospace = {
    enable = true;
    package = pkgs.aerospace;

    settings = {
      "config-version" = 2;

      after-startup-command = [
        "layout tiles horizontal" # Root container horizontal
      ];

      persistent-workspaces = ["1.Main" "2.Comms" "3.Dash" "4.Distracted"];

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

        shift-ctrl-alt-y = "focus left";
        shift-ctrl-alt-j = "focus down";
        shift-ctrl-alt-k = "focus up";
        shift-ctrl-alt-o = "focus right";

        shift-ctrl-alt-h = "swap --swap-focus left";
        shift-ctrl-alt-u = "swap --swap-focus down";
        shift-ctrl-alt-i = "swap --swap-focus up";
        shift-ctrl-alt-l = "swap --swap-focus right";

        shift-ctrl-alt-n = "move left";
        shift-ctrl-alt-m = "move down";
        shift-ctrl-alt-comma = "move up";
        shift-ctrl-alt-period = "move right";

        shift-ctrl-alt-left = "join-with left";
        shift-ctrl-alt-down = "join-with down";
        shift-ctrl-alt-up = "join-with up";
        shift-ctrl-alt-right = "join-with right";

        shift-ctrl-alt-quote = "balance-sizes";
        shift-ctrl-alt-pageUp = "resize smart +100";
        shift-ctrl-alt-pageDown = "resize smart -100";

        shift-ctrl-alt-semicolon = "workspace next";
        shift-ctrl-alt-4 = "move-node-to-workspace --wrap-around prev";
        shift-ctrl-alt-5 = "workspace --wrap-around prev";
        shift-ctrl-alt-6 = "workspace --wrap-around next";
        shift-ctrl-alt-equal = "move-node-to-workspace --wrap-around next";

        # Move workspace to monitor
        shift-ctrl-alt-leftSquareBracket = "move-workspace-to-monitor --wrap-around prev";
        shift-ctrl-alt-rightSquareBracket = "move-workspace-to-monitor --wrap-around next";

        # Move current window to monitor
        shift-ctrl-alt-9 = "move-node-to-monitor --wrap-around prev";
        shift-ctrl-alt-0 = "move-node-to-monitor --wrap-around next";

        # Summon Vivaldi to current workspace, dock to long edge at 1/3 size
        shift-ctrl-alt-a = "exec-and-forget ${aerospace-summon}/bin/aerospace-summon com.vivaldi.Vivaldi";
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
      ];
      # Default: new workspaces go to external monitor (if configured)
      on-focused-monitor-changed = ["move-mouse monitor-lazy-center"];

      workspace-to-monitor-force-assignment =
        # Comms always stays on built-in display
        {"2.Comms" = ["built-in"];}
        // lib.optionalAttrs (cfg.aerospace.externalMonitor != null) {
          # Everything else goes to external monitor when configured
          "1.Main" = [cfg.aerospace.externalMonitor "main"];
          "3.Dash" = [cfg.aerospace.externalMonitor "main"];
          "4.Distracted" = [cfg.aerospace.externalMonitor "main"];
        };
    };
  };
}
