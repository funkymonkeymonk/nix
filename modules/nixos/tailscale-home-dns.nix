{
  config,
  lib,
  ...
}:
with lib; let
  caddyApps = config.myConfig.caddy.apps or {};
  homeCaddyHosts =
    mapAttrsToList
    (_name: app: app.host)
    (filterAttrs (_name: app: hasSuffix ".home.buildingbananas.com" app.host) caddyApps);
  caddyRecords = map (host: "${host},100.89.187.92") homeCaddyHosts;
  homeRecords =
    caddyRecords
    ++ [
      # Zero still owns the Sunshine route in the home domain.
      "sunshine.home.buildingbananas.com,100.71.97.28"
    ];
in {
  # Tailscale's restricted DNS route for home.buildingbananas.com points at
  # Drlight. Resolve its Caddy app hostnames to Drlight's stable Tailscale IP,
  # while preserving the existing Zero-hosted Sunshine route.
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      interface = ["tailscale0"];
      bind-dynamic = true;
      no-resolv = true;
      domain-needed = true;
      server = [
        "/home.buildingbananas.com/192.168.1.1"
        "100.100.100.100"
      ];
      host-record = homeRecords;
    };
  };

  networking.firewall.interfaces.tailscale0 = {
    allowedUDPPorts = [53];
    allowedTCPPorts = [53];
  };

  systemd.services.dnsmasq = {
    after = ["tailscaled.service"];
    wants = ["tailscaled.service"];
  };
}
