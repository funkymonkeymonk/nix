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
    # opnix creates /run/secrets as root:root; the user-level Sunshine unit
    # needs directory traversal to read its own 0400 secret file.
    systemd.tmpfiles.rules = ["z /run/secrets 0750 root users -"];

    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true; # needed for Wayland
      openFirewall = true;
      settings = {
        # Allow a phone or another LAN browser to submit Moonlight's pairing PIN.
        origin_pin_allowed = "lan";
        origin_web_ui_allowed = "lan";
        sunshine_name = config.networking.hostName;
      };
    };

    # Apply the opnix-managed password immediately before Sunshine starts so
    # the credential is never embedded in the Nix store or service unit.
    systemd.user.services.sunshine.preStart = ''
      password_file=/run/secrets/sunshine-password
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
    systemd.user.services.sunshine.serviceConfig = {
      Restart = "on-failure";
    };
  };
}
