{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.myConfig.tailscale;
  # Check if this is NixOS by looking for NixOS-specific options
  isNixOS = builtins.hasAttr "boot" options;
  # Check if the opnix module is available
  hasOpnix = builtins.hasAttr "onepassword-secrets" (options.services or {});
  # Build vault-aware reference for the auth key
  authKeyRef =
    if lib.hasPrefix "op://" cfg.authKeyOpnixItem
    then cfg.authKeyOpnixItem
    else "op://${config.myConfig.onepassword.defaultVault}/${cfg.authKeyOpnixItem}";

  # Build tailscale up command flags
  tailscaleUpFlags = lib.concatStringsSep " " (
    ["-authkey \"\$auth_key\""]
    ++ lib.optionals cfg.exitNode ["--advertise-exit-node"]
    ++ lib.optionals (cfg.advertiseRoutes != []) ["--advertise-routes ${lib.concatStringsSep "," cfg.advertiseRoutes}"]
  );
in {
  options.myConfig.tailscale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Tailscale VPN with auto-connect via 1Password secrets";
    };
    authKeyOpnixItem = lib.mkOption {
      type = lib.types.str;
      default = "Tailscale/auth-key";
      description = "1Password item reference for Tailscale auth key. If the value does not start with 'op://', it is treated as 'Item/Field' and the default vault is prepended.";
    };
    exitNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise this machine as a Tailscale exit node";
    };
    advertiseRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional routes to advertise (CIDR notation, e.g. [\"10.0.0.0/24\"])";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Common config (packages available on both platforms)
    {
      environment.systemPackages = [pkgs.tailscale];
    }
    # NixOS-specific config (only on NixOS)
    (lib.optionalAttrs isNixOS {
      services.tailscale.enable = true;
      myConfig.onepassword.secrets.tailscaleAuthKey = {
        reference = authKeyRef;
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
    # Enable opnix secrets fetching when the opnix module is available
    (lib.optionalAttrs hasOpnix {
      services.onepassword-secrets.enable = true;
    })
  ]);
}
