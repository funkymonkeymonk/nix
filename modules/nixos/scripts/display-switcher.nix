{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.display-switcher;
in {
  options.services.display-switcher = {
    enable = mkEnableOption "Enable display switcher service";
    user = mkOption {
      type = types.str;
      default = "monkey";
      description = "User to run display switcher as";
    };
    virtualDisplay = mkOption {
      type = types.str;
      default = ":99";
      description = "Virtual display identifier";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "display-switcher" ''
        #!/usr/bin/env bash
        # Display switcher script for multi-session setup

        VIRTUAL_DISPLAY="''${VIRTUAL_DISPLAY:-:99}"
        PHYSICAL_DISPLAY="''${PHYSICAL_DISPLAY:-:0}"

        case "$1" in
          "virtual")
            echo "Switching to virtual display $VIRTUAL_DISPLAY"
            export DISPLAY=$VIRTUAL_DISPLAY
            ;;
          "physical")
            echo "Switching to physical display $PHYSICAL_DISPLAY"
            export DISPLAY=$PHYSICAL_DISPLAY
            ;;
          "detect")
            # Count connected displays
            COUNT=$(xrandr --query 2>/dev/null | grep " connected" | wc -l)
            echo "Connected displays: $COUNT"
            exit $COUNT
            ;;
          "status")
            echo "Current DISPLAY: $DISPLAY"
            echo "Virtual display: $VIRTUAL_DISPLAY"
            echo "Physical display: $PHYSICAL_DISPLAY"
            ;;
          *)
            echo "Usage: $0 {virtual|physical|detect|status}"
            echo "  virtual  - Set DISPLAY to virtual display ($VIRTUAL_DISPLAY)"
            echo "  physical - Set DISPLAY to physical display ($PHYSICAL_DISPLAY)"
            echo "  detect   - Count connected displays"
            echo "  status   - Show current display status"
            exit 1
            ;;
        esac
      '')
      xorg.xrandr
    ];
  };
}
