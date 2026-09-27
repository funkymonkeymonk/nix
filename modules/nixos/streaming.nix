# Sunshine game streaming for NixOS
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.streaming;
  sunshineUserServiceTrigger = pkgs.writeText "sunshine-user-service-trigger" (builtins.toJSON {
    settings = config.services.sunshine.settings;
    applications = config.services.sunshine.applications;
  });
in {
  options.myConfig.streaming = {
    enable = mkEnableOption "Sunshine game streaming";
  };

  config = mkIf cfg.enable {
    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true; # needed for Wayland
      openFirewall = true;
      settings = {
        # Gamescope exposes the console session through DRM/KMS. This is the
        # reliable capture path for a native Sunshine package on KDE Wayland.
        capture = "kms";
        # Allow a phone or another LAN browser to submit Moonlight's pairing PIN.
        origin_pin_allowed = "lan";
        origin_web_ui_allowed = "lan";
        csrf_allowed_origins = "https://sunshine.home.buildingbananas.com";
        sunshine_name = config.networking.hostName;
      };
      applications = {
        apps = [
          {
            name = "Desktop";
          }
          {
            name = "Steam Big Picture";
            prep-cmd = [
              {
                undo = "${pkgs.util-linux}/bin/setsid ${lib.getExe pkgs.steam} steam://close/bigpicture";
              }
            ];
            detached = [
              "${pkgs.util-linux}/bin/setsid ${lib.getExe pkgs.steam} steam://open/bigpicture"
            ];
            auto-detach = true;
          }
        ];
      };
    };

    # NixOS does not restart changed systemd.user units during a system switch.
    # Use a system service as the activation bridge so Sunshine receives the
    # new unit and configuration without requiring a logout or manual restart.
    systemd.services.sunshine-user-restart = {
      after = ["opnix-secrets.service"];
      restartTriggers = [
        ./streaming.nix
        config.services.sunshine.package
        sunshineUserServiceTrigger
      ];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.systemd}/bin/systemctl --machine=monkey@.host --user daemon-reload
        ${pkgs.systemd}/bin/systemctl --machine=monkey@.host --user restart sunshine.service
      '';
    };

    # Apply the opnix-managed password immediately before Sunshine starts so
    # the credential is never embedded in the Nix store or service unit.
    systemd.user.services.sunshine.preStart = ''
      password_file=/var/lib/opnix/secrets/sunshinePassword
      for attempt in $(seq 1 60); do
        if [ -r "$password_file" ]; then
          break
        fi
        sleep 1
      done
      if [ ! -r "$password_file" ]; then
        echo "Sunshine password secret is missing: $password_file" >&2
        exit 1
      fi
      ${pkgs.sunshine}/bin/sunshine --creds monkey "$(cat "$password_file")"
    '';
    systemd.user.services.sunshine.unitConfig = {
      After = ["graphical-session.target" "opnix-secrets.service"];
      Wants = ["graphical-session.target"];
    };
    systemd.user.services.sunshine.serviceConfig = {
      Restart = "on-failure";
      RestartSec = lib.mkForce "10s";
    };
  };
}
