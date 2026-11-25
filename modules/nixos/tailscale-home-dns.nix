{
  config,
  lib,
  ...
}:
with lib; let
  caddyApps = config.myConfig.caddy.apps or {};
  homeRecords =
    mapAttrsToList (_name: app: "${app.host},192.168.1.23")
    (filterAttrs (_name: app: hasSuffix ".home.buildingbananas.com" app.host) caddyApps)
    ++ ["sunshine.home.buildingbananas.com,100.71.97.28"];
in {
  # Serve the private home zone locally. The router must delegate this zone to
  # Drlight or advertise Drlight as a DNS server for LAN clients.
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      interface = ["eno1" "tailscale0"];
      bind-dynamic = true;
      no-resolv = true;
      domain-needed = true;
      server = [
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
