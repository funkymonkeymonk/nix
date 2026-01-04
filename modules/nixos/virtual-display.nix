{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.virtual-display;
in {
  options.services.virtual-display = {
    enable = mkEnableOption "Enable virtual display server";
    resolution = mkOption {
      type = types.str;
      default = "3840x2160";
      description = "Virtual display resolution";
    };
    user = mkOption {
      type = types.str;
      default = "monkey";
      description = "User to run virtual display as";
    };
  };

  config = mkIf cfg.enable {
    # Virtual display server package
    environment.systemPackages = with pkgs; [
      xorg.xorgserver
      xorg.xrandr
    ];

    # Systemd user service for virtual display
    systemd.user.services.virtual-display = {
      description = "Virtual display server for streaming";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.xorg.xorgserver}/bin/Xorg -noreset +extension GLX +extension RANDR +extension RENDER -logfile /tmp/vdisplay.log :99";
        Restart = "on-failure";
        Environment = "DISPLAY=:99";
      };
      wantedBy = ["graphical-session.target"];
    };
  };
}
