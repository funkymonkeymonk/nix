# Optional deployment-time hardware discovery.
# Keep filesystem probing out of reusable archetypes; machine declarations opt
# into this module explicitly when they are installed with nixos-facter.
{lib, ...}: {
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists /etc/nixos/facter.json) "/etc/nixos/facter.json";
}
