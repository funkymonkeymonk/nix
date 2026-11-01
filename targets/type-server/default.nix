{
  # Initial admin SSH access
  users.users.admin.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # Centralized logging: the shared server archetype enables Vector and this
  # host enables its local Loki destination. See modules/nixos/{vector,loki}.nix.
  myConfig.loki.enable = true;
  myConfig.prometheus.openFirewallTailscale = true;
  myConfig.alertmanager.enable = true;
}
