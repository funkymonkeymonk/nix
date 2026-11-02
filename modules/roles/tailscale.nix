{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.myConfig.tailscale;
  usesDeploymentOAuth = cfg.authKeyMode == "devenv-oauth";
  authKeyFile =
    if usesDeploymentOAuth
    then "/run/devenv/tailscale-auth-key"
    else "/run/secrets/tailscale-auth-key";
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
    ["--auth-key=file:${authKeyFile}"]
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
      description = "1Password item reference for static Tailscale auth keys. If the value does not start with 'op://', the default vault is prepended.";
    };
    authKeyMode = lib.mkOption {
      type = lib.types.enum ["opnix" "devenv-oauth"];
      default = "opnix";
      description = "How NixOS obtains an auth key: from OpNix or from a one-time key provisioned by the Devenv deployment task.";
    };
    authKeyTags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Tailscale tags assigned to devices authenticated with deployment-generated OAuth auth keys.";
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
    (lib.mkIf (isNixOS && !usesDeploymentOAuth) {
      myConfig.onepassword.secrets.tailscaleAuthKey = {
        reference = authKeyRef;
        path = "/run/secrets/tailscale-auth-key";
        mode = "0400";
        services = ["tailscale-autoconnect"];
      };
    })
    (lib.optionalAttrs isNixOS {
      services.tailscale.enable = true;
      systemd.services.tailscale-autoconnect = {
        description = "Connect this machine to Tailscale";
        after = ["network-pre.target" "tailscale.service"] ++ lib.optionals (!usesDeploymentOAuth) ["opnix-secrets.service"];
        wants = ["network-pre.target" "tailscale.service"] ++ lib.optionals (!usesDeploymentOAuth) ["opnix-secrets.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig.Type = "oneshot";
        script = ''
          sleep 2
          status="$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.BackendState // empty' 2>/dev/null || true)"
          if [ "$status" = "Running" ]; then
            echo "Tailscale already connected"
            exit 0
          fi
          auth_key_file=${lib.escapeShellArg authKeyFile}
          if [ -r "$auth_key_file" ]; then
            ${lib.optionalString usesDeploymentOAuth ''trap 'rm -f -- "$auth_key_file"' EXIT''}
            ${pkgs.tailscale}/bin/tailscale up ${tailscaleUpFlags}
          else
            ${
            if usesDeploymentOAuth
            then ''
              echo "No deployment auth key is present; run the Devenv machine deploy task to authenticate this node."
              exit 0
            ''
            else ''
              echo "Error: Tailscale auth key not found at /run/secrets/tailscale-auth-key"
              echo "Ensure opnix is configured and the 1Password item ${cfg.authKeyOpnixItem} exists"
              exit 1
            ''
          }
          fi
        '';
      };
      assertions = [
        {
          assertion = !usesDeploymentOAuth || cfg.authKeyTags != [];
          message = "myConfig.tailscale.authKeyTags must be set when authKeyMode is devenv-oauth.";
        }
      ];
    })
    # Enable opnix secrets fetching when the opnix module is available
    (lib.optionalAttrs hasOpnix {
      services.onepassword-secrets.enable = true;
    })
  ]);
}
