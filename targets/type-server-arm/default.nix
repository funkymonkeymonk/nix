{lib, ...}: let
  sshPublicKey = import ../../library/ssh-public-key.nix;
in {
  # Initial monkey SSH access
  users.users.monkey.openssh.authorizedKeys.keys = [sshPublicKey];

  # This target is ARM64, so neither x86 microcode package applies.
  hardware.cpu.intel.updateMicrocode = lib.mkForce false;
  hardware.cpu.amd.updateMicrocode = lib.mkForce false;

  myConfig.nodeExporter.openFirewallInterfaces = [];
}
