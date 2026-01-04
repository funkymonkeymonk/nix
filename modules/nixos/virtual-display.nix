{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.virtual-display;
  userUid = config.users.users.${cfg.user}.uid;
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
    ];

    # Systemd user service for virtual display
    systemd.user.services.virtual-display = {
      description = "Virtual display server for streaming";
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "/tmp";

        # Security hardening
        PrivateTmp = true;
        PrivateNetwork = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;

        # Authentication setup
        ExecStartPre = [
          "${pkgs.xorg.xauth}/bin/xauth -f ${xauthFile} remove ${displayName} 2>/dev/null || true"
          "${pkgs.xorg.xauth}/bin/xauth -f ${xauthFile} add ${displayName} . `mcookie`"
        ];

        # Secure Xorg startup with authentication and no network access
        ExecStart = "${pkgs.xorg.xorgserver}/bin/Xorg -noreset +extension GLX +extension RANDR +extension RENDER -logfile /tmp/vdisplay.log -auth ${xauthFile} -nolisten tcp -nolisten local ${displayName}";

        # Cleanup on stop
        ExecStopPost = [
          "${pkgs.xorg.xauth}/bin/xauth -f ${xauthFile} remove ${displayName} 2>/dev/null || true"
        ];

        Restart = "on-failure";
        Environment = "DISPLAY=${displayName} XAUTHORITY=${xauthFile}";
      };
      wantedBy = ["graphical-session.target"];
    };
  };
}
