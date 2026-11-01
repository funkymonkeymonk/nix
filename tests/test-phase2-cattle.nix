{
  pkgs,
  self,
  ...
}: let
  hasConfig = name: builtins.hasAttr name self.nixosConfigurations;
  hasTargetModule = name: builtins.pathExists (../targets + "/${name}/default.nix");
  flakeText = builtins.readFile ../flake.nix;

  headlessServerUsers = ["type-server" "type-nas" "type-server-arm" "drlight"];
  sshKeyHosts = ["type-server" "type-nas" "type-server-arm" "drlight"];
  monkeySshKey = import ../library/ssh-public-key.nix;

  headlessServerUsersTest = pkgs.runCommand "test-headless-server-users" {} ''
    echo "=== Testing headless server user accounts ==="
    ${builtins.concatStringsSep "\n" (map (
        hostname: let
          users = self.nixosConfigurations.${hostname}.config.users.users;
          hasMonkey = builtins.hasAttr "monkey" users;
          hasAdmin = builtins.hasAttr "admin" users;
        in
          if hasMonkey && !hasAdmin
          then ''echo "  ${hostname}: monkey exists and admin is absent: OK"''
          else ''echo "  FAIL: ${hostname} must have monkey and no admin account"; exit 1''
      )
      headlessServerUsers)}
    ${builtins.concatStringsSep "\n" (map (
        hostname: let
          cfg = self.nixosConfigurations.${hostname}.config;
          hasWheel = builtins.elem "wheel" cfg.users.users.monkey.extraGroups;
          hasPasswordlessSudo = !cfg.security.sudo.wheelNeedsPassword;
        in
          if !cfg.users.mutableUsers && hasWheel && hasPasswordlessSudo
          then ''echo "  ${hostname}: immutable users and passwordless monkey sudo: OK"''
          else ''echo "  FAIL: ${hostname} must disable mutable users and grant monkey passwordless sudo via wheel"; exit 1''
      )
      headlessServerUsers)}
    ${builtins.concatStringsSep "\n" (map (
        hostname: let
          cfg = self.nixosConfigurations.${hostname}.config;
          users = cfg.users.users;
          hasMonkey = builtins.hasAttr "monkey" users;
          hasKey = hasMonkey && builtins.elem monkeySshKey (users.monkey.openssh.authorizedKeys.keys or []);
          keyAuthenticationOnly = cfg.services.openssh.enable && cfg.services.openssh.settings.PubkeyAuthentication && !cfg.services.openssh.settings.PasswordAuthentication;
        in
          if hasKey && keyAuthenticationOnly
          then ''echo "  ${hostname}: monkey SSH key authentication is enabled: OK"''
          else ''echo "  FAIL: ${hostname} must authorize the SSH key for monkey and require key authentication"; exit 1''
      )
      sshKeyHosts)}
    touch $out
  '';

  phase2CattleTest = pkgs.runCommand "test-phase2-cattle" {} ''
    echo "=== Testing Cattle NixOS Configs ==="
    echo ""

    # type-server, type-server-arm, and type-desktop all use libraryLib.mkNixosSystem
    # directly now (no more -v2 twins — retired after parity verification)
    ${
      if hasConfig "type-server"
      then ""
      else ''echo "FAIL: type-server not found"; exit 1''
    }
    echo "  type-server: defined ✓"

    ${
      if hasConfig "type-server-arm"
      then ""
      else ''echo "FAIL: type-server-arm not found"; exit 1''
    }
    echo "  type-server-arm: defined ✓"

    ${
      if hasConfig "type-desktop"
      then ""
      else ''echo "FAIL: type-desktop not found"; exit 1''
    }
    echo "  type-desktop: defined ✓"

    ${
      if hasTargetModule "type-server"
      then ""
      else ''echo "FAIL: type-server target module not found"; exit 1''
    }
    echo "  type-server target module: defined ✓"

    ${
      if hasTargetModule "type-server-arm"
      then ""
      else ''echo "FAIL: type-server-arm target module not found"; exit 1''
    }
    echo "  type-server-arm target module: defined ✓"

    ${
      if hasTargetModule "type-desktop"
      then ""
      else ''echo "FAIL: type-desktop target module not found"; exit 1''
    }
    echo "  type-desktop target module: defined ✓"

    ${
      if builtins.pathExists ../library/machines/catalog.nix
      then ''echo "  canonical machine catalog: defined ✓"''
      else ''echo "FAIL: canonical machine catalog not found"; exit 1''
    }

    ${
      if pkgs.lib.hasInfix "./library/machines/flake-parts.nix" flakeText
      then ''echo "  generated flake-parts projection imported by flake.nix ✓"''
      else ''echo "FAIL: generated machine projection not imported by flake.nix"; exit 1''
    }

    ${
      if builtins.pathExists ../targets/hardware-facter.nix
      then ''echo "  explicit hardware-facter module: defined ✓"''
      else ''echo "FAIL: explicit hardware-facter module not found"; exit 1''
    }

    echo ""
    echo "All cattle tests passed"
    touch $out
  '';
in {
  inherit headlessServerUsersTest phase2CattleTest;
}
