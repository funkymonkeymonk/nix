{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.tailscale;
  authKeyFile = "/tmp/devenv-tailscale-auth-key";
  tailscaleUpArguments = import ./up-arguments.nix {inherit lib;};
  tailscaleUpFlags = tailscaleUpArguments cfg authKeyFile;

  authScript = pkgs.writeShellScript "tailscale-oauth-autoconnect" ''
    exec ${pkgs.bash}/bin/bash ${../../../scripts/tailscale-darwin-autoconnect.sh} \
      ${lib.escapeShellArgs [
      authKeyFile
      "${pkgs.tailscale}/bin/tailscale"
      "${pkgs.jq}/bin/jq"
      "/bin/sleep"
      "30"
      "2"
      tailscaleUpFlags
    ]}
  '';

  serveScript = name: mapping:
    pkgs.writeShellScript "tailscale-serve-${name}" ''
      set -euo pipefail

      while true; do
        TAILSCALE_IP=$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null || true)
        if [ -n "$TAILSCALE_IP" ] && ${pkgs.curl}/bin/curl \
            --silent --fail --connect-timeout 2 --max-time 5 \
            ${lib.escapeShellArg mapping.readinessUrl} >/dev/null; then
          exec ${pkgs.tailscale}/bin/tailscale serve --bg \
            --http=${toString mapping.port} \
            ${lib.escapeShellArg mapping.target}
        fi
        /bin/sleep 5
      done
    '';

  serveDaemons = lib.mapAttrs' (name: mapping:
    lib.nameValuePair "tailscale-serve-${name}" {
      command = serveScript name mapping;
      serviceConfig = {
        Label = "org.nix-community.tailscale-serve-${name}";
        RunAtLoad = true;
        KeepAlive = {SuccessfulExit = false;};
        StandardOutPath = "/tmp/tailscale-serve-${name}.log";
        StandardErrorPath = "/tmp/tailscale-serve-${name}.error.log";
      };
    })
  cfg.serve;
in {
  config = lib.mkIf cfg.enable {
    services.tailscale.enable = true;
    launchd.daemons =
      {
        tailscaled.serviceConfig.KeepAlive = true;
        tailscale-autoconnect = {
          command = authScript;
          serviceConfig = {
            Label = "org.nix-community.tailscale-autoconnect";
            RunAtLoad = true;
            KeepAlive = {SuccessfulExit = false;};
            WatchPaths = [authKeyFile];
            StandardOutPath = "/tmp/tailscale-autoconnect.log";
            StandardErrorPath = "/tmp/tailscale-autoconnect.error.log";
          };
        };
      }
      // serveDaemons;
  };
}
