# Minimal SSH-ready NixOS live target. Installation is controlled by the workstation.
{
  pkgs,
  lib,
  modulesPath,
  ...
}: let
  installerReady = pkgs.callPackage ../../packages/installer-ready {};
  sshPublicKey = import ../../library/ssh-public-key.nix;
in {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  isoImage = {
    edition = "installer";
    volumeID = "NIXOS_INSTALLER";
    makeEfiBootable = true;
    makeUsbBootable = true;
  };

  boot.loader.systemd-boot.enable = lib.mkForce false;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  environment.systemPackages = with pkgs; [
    iproute2
    openssh
    pciutils
    usbutils
    util-linux
    installerReady
  ];

  networking = {
    hostName = "nixos-installer";
    networkmanager.enable = true;
    useDHCP = lib.mkDefault true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
  };

  users.users.root = {
    openssh.authorizedKeys.keys = [sshPublicKey];
    initialHashedPassword = "";
  };

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
  };

  security.sudo.wheelNeedsPassword = false;

  services.getty = {
    autologinUser = lib.mkForce "nixos";
    greetingLine = lib.mkForce "\nWelcome to the SSH-ready NixOS live target!\n";
    helpLine = lib.mkForce "\nRead the readiness report and use the named workstation install flow.\n";
  };

  programs.bash.loginShellInit = lib.mkAfter ''
    if [ "$(tty)" = "/dev/tty1" ]; then
      ${installerReady}/bin/installer-ready
    fi
  '';

  users.motd = ''
    SSH-ready NixOS live target

    Run installer-ready to view current network addresses and the SSH host-key
    fingerprint. Verify the SSH host-key fingerprint over a trusted channel
    before trusting this target. Set machines.<name>.target.host in the ignored
    devenv.local.nix, then run:
      devenv tasks run machines:install --input machine=<name>

    Machine selection, credentials, review, and installation stay on the
    workstation. This live target does not partition, format, or install locally.
  '';

  system.stateVersion = "25.05";
}
