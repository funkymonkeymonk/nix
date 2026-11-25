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
  caddyInterfaceNames =
    concatMap (host: [
      "${host},eno1/4"
      "${host},tailscale0/4"
    ])
    homeCaddyHosts;
  homeRecords = [
    # Zero still owns the Sunshine route in the home domain.
    "sunshine.home.buildingbananas.com,100.71.97.28"
  ];
in {
  # LAN and tailnet clients send home-domain DNS queries to Drlight. Return the
  # address from the interface that received the query for each Caddy app.
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      interface = ["eno1" "tailscale0"];
      bind-dynamic = true;
      localise-queries = true;
      no-resolv = true;
      domain-needed = true;
      interface-name = caddyInterfaceNames;
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
