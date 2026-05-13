{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.myConfig.roles.tailscale;
  # Check if this is NixOS by looking for NixOS-specific options
  isNixOS = builtins.hasAttr "boot" options;

  # Build tailscale up command flags
  tailscaleUpFlags = lib.concatStringsSep " " (
    ["-authkey \"\$auth_key\""]
    ++ lib.optionals cfg.exitNode ["--advertise-exit-node"]
    ++ lib.optionals (cfg.advertiseRoutes != []) ["--advertise-routes ${lib.concatStringsSep "," cfg.advertiseRoutes}"]
  );
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Common config (packages available on both platforms)
    {
      environment.systemPackages = [pkgs.tailscale];
    }
    # NixOS-specific config (only on NixOS)
    (lib.optionalAttrs isNixOS {
      services.tailscale.enable = true;
      myConfig.onepassword.secrets.tailscaleAuthKey = {
        reference = cfg.authKeyOpnixItem;
        path = "/run/secrets/tailscale-auth-key";
        mode = "0400";
        services = ["tailscale-autoconnect"];
      };
      systemd.services.tailscale-autoconnect = {
        description = "Automatic connection to Tailscale";
        after = ["network-pre.target" "tailscale.service" "onepassword-secrets.service"];
        wants = ["network-pre.target" "tailscale.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig.Type = "oneshot";
        script = ''
          sleep 2
          status="$(${pkgs.tailscale}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)"
          if [ "$status" = "Running" ]; then
            echo "Tailscale already connected"
            exit 0
          fi
          if [ -f /run/secrets/tailscale-auth-key ]; then
            auth_key=$(cat /run/secrets/tailscale-auth-key)
            ${pkgs.tailscale}/bin/tailscale up ${tailscaleUpFlags}
          else
            echo "Error: Tailscale auth key not found at /run/secrets/tailscale-auth-key"
            echo "Ensure opnix is configured and the 1Password item ${cfg.authKeyOpnixItem} exists"
            exit 1
          fi
        '';
      };
    })
  ]);
}
