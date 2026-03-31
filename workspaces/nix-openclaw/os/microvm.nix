# Microvm platform configuration
# Stripped down for VM guests - no boot config needed (microvm.nix handles it)
{lib, ...}: {
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Minimal footprint
  documentation.enable = lib.mkDefault false;
  services.xserver.enable = lib.mkDefault false;
}
