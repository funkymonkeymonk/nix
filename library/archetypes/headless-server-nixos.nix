{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    inputs.disko.nixosModules.disko
  ];

  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;
    onepassword = {
      tokenFile = "/etc/opnix/token";
      defaultVault = "Homelab";
    };
    roles.tailscale = {
      enable = true;
      authKeyOpnixItem = "Tailscale Auth Key/credential";
    };
  };

  hardware.facter.reportPath = lib.mkIf (builtins.pathExists /etc/nixos/facter.json) "/etc/nixos/facter.json";

  users.users.root.openssh.authorizedKeys.keys = [];
  users.users.admin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [];
  };

  security.sudo.wheelNeedsPassword = false;

  boot = {
    loader.systemd-boot.enable = lib.mkDefault true;
    loader.efi.canTouchEfiVariables = lib.mkDefault true;
    kernelModules = lib.optionals pkgs.stdenv.hostPlatform.isx86_64 ["kvm-intel" "kvm-amd"];
  };

  nix.settings.experimental-features = ["nix-command" "flakes"];

  networking = {
    useDHCP = lib.mkDefault true;
    dhcpcd.extraConfig = ''
      option host_name
      send host-name = ""
    '';
    firewall = {
      enable = true;
      allowedTCPPorts = [22];
    };
  };

  services.xserver.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
      PasswordAuthentication = false;
      AllowAgentForwarding = true;
    };
  };

  environment.systemPackages = with pkgs; [
    qemu
    virtiofsd
  ];

  time.timeZone = "America/New_York";

  system.stateVersion = "25.05";
}
