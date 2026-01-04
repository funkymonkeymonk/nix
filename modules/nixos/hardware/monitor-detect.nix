{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.hardware.monitor-detect;
in {
  options.hardware.monitor-detect = {
    enable = mkEnableOption "Enable hardware monitor detection with udev rules";
    user = mkOption {
      type = types.str;
      default = "monkey";
      description = "User to run monitor detection services as";
    };
    virtualDisplay = mkOption {
      type = types.str;
      default = ":99";
      description = "Virtual display identifier";
    };
  };

  config = mkIf cfg.enable {
    # Udev rules for monitor hotplug detection
    services.udev.extraRules = ''
      # Monitor hotplug detection for DRM/DisplayPort
      ACTION=="change", SUBSYSTEM=="drm", ENV{DISPLAY}=="", RUN+="${pkgs.systemd}/bin/systemctl start monitor-hotplug.service"

      # HDMI monitor hotplug
      ACTION=="change", KERNEL=="card0", SUBSYSTEM=="drm", ENV{HOTPLUG}=="1", RUN+="${pkgs.systemd}/bin/systemctl start monitor-hotplug.service"

      # DisplayPort monitor hotplug
      ACTION=="change", KERNEL=="card0", SUBSYSTEM=="drm", ATTR{status}=="connected", RUN+="${pkgs.systemd}/bin/systemctl start monitor-hotplug.service"
    '';

    # Packages needed for monitor detection
    environment.systemPackages = with pkgs; [
      xorg.xrandr
      systemd
    ];

    # Systemd services for monitor detection
    systemd = {
      services.monitor-state = {
        description = "Monitor state tracking service";
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "monitor-state-start" ''
            # Initialize monitor state file
            MONITOR_STATE_FILE="/tmp/monitor-state"
            echo "headless" > "$MONITOR_STATE_FILE"

            # Check current monitor status
            CONNECTED_COUNT=$(${pkgs.xorg.xrandr}/bin/xrandr --query 2>/dev/null | grep " connected" | wc -l)
            if [ "$CONNECTED_COUNT" -gt 0 ]; then
              echo "physical" > "$MONITOR_STATE_FILE"
            fi
          '';
          ExecStop = pkgs.writeShellScript "monitor-state-stop" ''
            # Clean up monitor state file
            rm -f "/tmp/monitor-state"
          '';
        };
        wantedBy = ["multi-user.target"];
      };

      services.monitor-hotplug = {
        description = "Monitor hotplug detection service";
        after = ["monitor-state.service"];
        requires = ["monitor-state.service"];
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          ExecStart = pkgs.writeShellScript "monitor-hotplug-handler" ''
            MONITOR_STATE_FILE="/tmp/monitor-state"

            # Wait a moment for the display to settle
            sleep 2

            # Count connected monitors
            CONNECTED_COUNT=$(${pkgs.xorg.xrandr}/bin/xrandr --query 2>/dev/null | grep " connected" | wc -l)

            # Update state based on connection status
            if [ "$CONNECTED_COUNT" -gt 0 ]; then
              echo "physical" > "$MONITOR_STATE_FILE"
              echo "Physical monitor detected, ensuring virtual display compatibility"

              # Start virtual display if not already running
              systemctl --user is-active --quiet virtual-display || systemctl --user start virtual-display
            else
              echo "headless" > "$MONITOR_STATE_FILE"
              echo "No physical monitor detected, running headless with virtual display"

              # Ensure virtual display is running for headless operation
              systemctl --user is-active --quiet virtual-display || systemctl --user start virtual-display
            fi
          '';
        };
      };
    };
  };
}
