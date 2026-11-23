{
  pkgs,
  self ? null,
  ...
}: let
  inherit (pkgs) lib;

  skipped = pkgs.runCommand "test-drlight-media-indexers-skipped" {} ''
    echo "Skipped: self not provided"
    touch $out
  '';

  checks =
    if self == null
    then null
    else let
      drlight = self.nixosConfigurations.drlight.config;
      prowlarr = drlight.services.prowlarr;
      prowlarrSettings = prowlarr.settings or {};
      prowlarrServer = prowlarrSettings.server or {};
      prowlarrAuth = prowlarrSettings.auth or {};
      prowlarrUpdate = prowlarrSettings.update or {};
      flaresolverr = drlight.services.flaresolverr;
      prowlarrPort = prowlarrServer.port or 9696;
      prowlarrVersion = prowlarr.package.version;
      flaresolverrPort = flaresolverr.port or 8191;
      globalPorts = drlight.networking.firewall.allowedTCPPorts or [];
      interfaces = drlight.networking.firewall.interfaces or {};
      eno1Ports = (interfaces.eno1 or {}).allowedTCPPorts or [];
      tailscalePorts = (interfaces.tailscale0 or {}).allowedTCPPorts or [];
      caddyApps = drlight.myConfig.caddy.apps or {};
      assertTrue = name: condition:
        if condition
        then ''echo "  ${name}: OK"''
        else ''echo ${lib.escapeShellArg "FAIL: ${name}"}; failures=1'';
      assertEqual = name: expected: actual: assertTrue name (expected == actual);
    in
      pkgs.runCommand "test-drlight-media-indexers" {} ''
        failures=0
        echo "=== Testing Drlight-local Prowlarr and FlareSolverr ==="

        ${assertTrue "Prowlarr enabled on Drlight" prowlarr.enable}
        ${assertTrue "Prowlarr package meets the seedbox backup version floor" (lib.versionAtLeast prowlarrVersion "3.0.2.5780")}
        ${assertEqual "Prowlarr uses port 9696" 9696 prowlarrPort}
        ${assertEqual "Prowlarr binds its UI to all interfaces behind the firewall" "*" (prowlarrServer.bindaddress or null)}
        ${assertEqual "Prowlarr uses Forms authentication" "Forms" (prowlarrAuth.method or null)}
        ${assertEqual "Prowlarr requires authentication" "Enabled" (prowlarrAuth.required or null)}
        ${assertEqual "Prowlarr update mechanism is external" "external" (prowlarrUpdate.mechanism or null)}
        ${assertEqual "Prowlarr in-app updates are disabled" false (prowlarrUpdate.automatically or null)}
        ${assertTrue "Prowlarr does not open a global firewall rule" (prowlarr.openFirewall == false && !(builtins.elem prowlarrPort globalPorts))}
        ${assertTrue "Prowlarr UI is allowed on the home LAN" (builtins.elem prowlarrPort eno1Ports)}
        ${assertTrue "Prowlarr UI is allowed on Tailscale" (builtins.elem prowlarrPort tailscalePorts)}
        ${assertTrue "FlareSolverr enabled on Drlight" flaresolverr.enable}
        ${assertEqual "FlareSolverr uses port 8191" 8191 flaresolverrPort}
        ${assertTrue "FlareSolverr does not open a global firewall rule" (flaresolverr.openFirewall == false && !(builtins.elem flaresolverrPort globalPorts))}
        ${assertTrue "FlareSolverr is not allowed on the home LAN" (!(builtins.elem flaresolverrPort eno1Ports))}
        ${assertTrue "FlareSolverr is not allowed on Tailscale" (!(builtins.elem flaresolverrPort tailscalePorts))}
        ${assertTrue "Prowlarr and FlareSolverr have no Caddy routes" (!(caddyApps ? prowlarr) && !(caddyApps ? flaresolverr))}

        if [ "$failures" -ne 0 ]; then exit 1; fi
        echo "All Drlight media-indexer tests passed"
        touch $out
      '';
in {
  drlightMediaIndexersTest =
    if checks == null
    then skipped
    else checks;
}
