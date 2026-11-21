{lib, ...}:
with lib; let
  # Route all private service names to Drlight's LAN address. Caddy provides
  # the service-specific routing after DNS reaches this host.
  homeRecords = ["*.home.buildingbananas.com,192.168.1.23"];
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
