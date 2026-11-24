{config, ...}: let
  prowlarrPort = config.services.prowlarr.settings.server.port;
in {
  services.prowlarr = {
    enable = true;
    openFirewall = false;
    settings = {
      server = {
        bindaddress = "*";
        urlbase = "";
      };
      auth = {
        method = "Forms";
        required = "Enabled";
      };
      update = {
        mechanism = "external";
        automatically = false;
      };
    };
  };

  services.flaresolverr = {
    enable = true;
    openFirewall = false;
  };

  networking.firewall.interfaces = {
    eno1.allowedTCPPorts = [prowlarrPort];
    "tailscale0".allowedTCPPorts = [prowlarrPort];
  };
}
