# Central NixOS observability backend.
# Import this profile only on the host that stores and evaluates telemetry.
{...}: {
  imports = [
    ../../modules/nixos/prometheus.nix
    ../../modules/nixos/loki.nix
    ../../modules/nixos/alertmanager.nix
    ../../modules/nixos/grafana.nix
  ];

  myConfig = {
    prometheus.enable = true;
    loki = {
      enable = true;
      openFirewallTailscale = true;
    };
    alertmanager.enable = true;
    grafana.enable = true;
  };
}
