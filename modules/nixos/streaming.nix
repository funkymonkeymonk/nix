# Sunshine game streaming for NixOS
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.streaming;
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
        # Allow a phone or another LAN browser to submit Moonlight's pairing PIN.
        origin_pin_allowed = "lan";
        origin_web_ui_allowed = "lan";
        csrf_allowed_origins = "https://sunshine.home.buildingbananas.com";
        sunshine_name = config.networking.hostName;
      };
    };

    # Opnix runs as a system service, while Sunshine runs in the user's
    # graphical systemd instance. Bridge secret-triggered restarts explicitly.
    systemd.services.sunshine-user-restart = {
      after = ["opnix-secrets.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl --machine=monkey@.host --user restart sunshine.service";
      };
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
