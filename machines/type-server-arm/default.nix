{lib, ...}: {
  # This target is ARM64, so neither x86 microcode package applies.
  hardware.cpu.intel.updateMicrocode = lib.mkForce false;
  hardware.cpu.amd.updateMicrocode = lib.mkForce false;

  myConfig.nodeExporter.openFirewallInterfaces = [];
}
