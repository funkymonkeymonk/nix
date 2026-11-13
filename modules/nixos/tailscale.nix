{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.tailscale or {};
  authKeyFile = "/run/devenv/tailscale-auth-key";
  tailscaleUpArguments = import ../services/tailscale/up-arguments.nix {inherit lib;};
  tailscaleUpFlags =
    tailscaleUpArguments {
      exitNode = cfg.exitNode or false;
      advertiseRoutes = cfg.advertiseRoutes or [];
    }
    authKeyFile;
in {
  config = lib.mkIf (cfg.enable or false) {
    services.tailscale.enable = true;
    systemd.services.tailscale-autoconnect = {
      description = "Connect this machine to Tailscale with a deployment-generated auth key";
      after = ["network-pre.target" "tailscale.service"];
      wants = ["network-pre.target" "tailscale.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig.Type = "oneshot";
      script = ''
        sleep 2
        status="$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.BackendState // empty' 2>/dev/null || true)"
        if [ "$status" = "Running" ]; then
          echo "Tailscale already connected"
          exit 0
        fi
        if [ "$status" != "NeedsLogin" ]; then
          echo "Tailscale backend state is unknown or unsupported ('$status'); refusing to consume the deployment auth key." >&2
          exit 1
        fi

        auth_key_file=${lib.escapeShellArg authKeyFile}
        if [ -r "$auth_key_file" ]; then
          trap 'rm -f -- "$auth_key_file"' EXIT
          ${pkgs.tailscale}/bin/tailscale up ${tailscaleUpFlags}
        else
          echo "No deployment auth key found; use the named Devenv Machines deployment to enroll this machine." >&2
        fi
      '';
    };
    assertions = [
      {
        assertion = !(cfg.enable or false) || (cfg.authKeyTags or []) != [];
        message = "myConfig.tailscale.authKeyTags must not be empty for deployment-generated OAuth auth keys.";
      }
    ];
  };
}
