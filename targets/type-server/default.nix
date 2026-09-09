{
  # Initial admin SSH access
  users.users.admin.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # Centralized logging: Vector ships journald logs to a local
  # Loki instance on this host. See modules/nixos/{vector,loki}.nix.
  myConfig.vector.enable = true;
  myConfig.loki.enable = true;
  myConfig.prometheus = {
    enable = true;
    openFirewallTailscale = true;
  };
  myConfig.nodeExporter.enable = true;
  myConfig.alertmanager.enable = true;
}
