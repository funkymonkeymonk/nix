{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.virtual-display;
  # Hardcode UID for monkey user since it's the primary user in this setup
  userUid =
    if cfg.user == "monkey"
    then 1000
    else config.users.users.${cfg.user}.uid or 1000;
  xauthFile = "/run/user/${builtins.toString userUid}/.Xauthority";
  displayNumber = "99";
  displayName = ":${displayNumber}";
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
    group = mkOption {
      type = types.str;
      default = "users";
      description = "Group to run virtual display as";
    };
  };

  config = mkIf cfg.enable {
    # Virtual display server package
    environment.systemPackages = with pkgs; [
      xorg.xorgserver
      xorg.xrandr
      xorg.xauth
      xorg.xvfb
    ];

    # System-level service for virtual display (avoids user permission issues)
    systemd.services.virtual-display = {
      description = "Virtual display server for streaming";
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "video"; # Use video group for display access
        WorkingDirectory = "/tmp";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;

        # Use Xvfb with simpler parameters for better compatibility
        ExecStart = "${pkgs.xorg.xvfb}/bin/Xvfb ${displayName} -screen 0 ${cfg.resolution}x24";

        Restart = "on-failure";
        RestartSec = 3;
        Environment = "DISPLAY=${displayName} XAUTHORITY=${xauthFile}";
      };
      wantedBy = ["multi-user.target"];
    };

    # Add user to video group for display access
    users.users.${cfg.user}.extraGroups = ["video"];
  };
}
