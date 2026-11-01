{
  pkgs,
  self,
  ...
}: let
  lib = pkgs.lib;
  config = self.nixosConfigurations.installer-iso.config;
  installerReady = self.packages.x86_64-linux.installer-ready;
  publicAuthorizedKey = import ../library/ssh-public-key.nix;
  packageNames = map (package: package.name or "") config.environment.systemPackages;
  sshSettings = config.services.openssh.settings;
  loginShellInit = config.programs.bash.loginShellInit;
  motd = config.users.motd;
  configChecks = assert config.networking.networkmanager.enable;
  assert config.services.openssh.enable;
  assert builtins.elem "flakes" config.nix.settings.experimental-features;
  assert builtins.elem installerReady config.environment.systemPackages;
  assert lib.hasInfix "installer-ready" loginShellInit;
  assert lib.hasInfix "/dev/tty1" loginShellInit;
  assert lib.hasInfix "machines.<name>.target.host" motd;
  assert lib.hasInfix "devenv tasks run machines:install --input machine=<name>" motd;
  assert lib.hasInfix "Verify the SSH host-key fingerprint" motd;
  assert !(config.systemd.services ? installer-tty);
  assert !(builtins.elem "disko" packageNames);
  assert !(builtins.elem "nixos-flake-installer" packageNames);
  assert !(builtins.elem "nixos-installer-dev-mode" packageNames);
  assert !(builtins.elem "op" packageNames);
  assert !(builtins.elem "secretspec" packageNames);
  # Preserve the explicitly reviewed live-ISO SSH and sudo access policy.
  assert sshSettings.PermitRootLogin == "prohibit-password";
  assert sshSettings.PasswordAuthentication == false;
  assert sshSettings.PubkeyAuthentication == true;
  assert config.security.sudo.wheelNeedsPassword == false;
  assert config.users.users.root.openssh.authorizedKeys.keys == [publicAuthorizedKey]; true;
  helperTest =
    pkgs.runCommand "installer-ready-helper-tests" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.gnugrep];
    } ''
      INSTALLER_READY_SCRIPT=${../packages/installer-ready/installer-ready.sh} \
        ${pkgs.bash}/bin/bash ${./test-installer-ready.sh}
      ${
        if pkgs.stdenv.hostPlatform.isLinux
        then ''
          ${installerReady}/bin/installer-ready > "$TMPDIR/installer-ready-package-output"
          ${pkgs.gnugrep}/bin/grep -F 'The workstation owns machine selection' "$TMPDIR/installer-ready-package-output"
        ''
        else ""
      }
      touch $out
    '';
in {
  installerReady = assert configChecks; helperTest;
}
