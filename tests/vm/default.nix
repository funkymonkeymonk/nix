# NixOS VM integration tests
# These tests boot a minimal NixOS VM and verify system behavior.
# Only runs on x86_64-linux (NixOS testing framework requirement).
{pkgs, ...}: let
  # Helper to create a NixOS test with our modules
  mkTest = {
    name,
    testScript,
    extraModules ? [],
    roles ? {},
  }:
    pkgs.testers.nixosTest {
      inherit name;
      nodes.machine = {...}: {
        imports =
          [
            ../../modules/common/options.nix
            ../../modules/common/shell.nix
            ../../modules/roles/default.nix
            ../../modules/nixos/base.nix
          ]
          ++ extraModules;

        config = {
          myConfig = {
            users = [
              {
                name = "testuser";
                email = "test@example.com";
                fullName = "Test User";
                isAdmin = true;
                sshIncludes = [];
              }
            ];
            # Disable features that need external dependencies
            onepassword.enable = false;
            cachix.enable = false;
            inherit roles;
          };

          # Minimal VM config
          system.stateVersion = "25.05";
          virtualisation.memorySize = 1024;
        };
      };
      inherit testScript;
    };
in {
  # Test that users are created with correct properties
  vm-users = mkTest {
    name = "vm-test-users";
    testScript = ''
      machine.wait_for_unit("multi-user.target")

      # Verify user exists
      machine.succeed("id testuser")

      # Verify user is in expected groups
      groups = machine.succeed("groups testuser")
      assert "wheel" in groups, f"testuser not in wheel group: {groups}"
      assert "networkmanager" in groups, \
          f"testuser not in networkmanager group: {groups}"

      # Verify home directory exists
      machine.succeed("test -d /home/testuser")

      # Verify shell is zsh
      shell = machine.succeed("getent passwd testuser | cut -d: -f7")
      assert "zsh" in shell, f"Expected zsh shell, got: {shell}"
    '';
  };

  # Test that SSH service starts and is accessible
  vm-ssh = mkTest {
    name = "vm-test-ssh";
    testScript = ''
      machine.wait_for_unit("sshd.service")
      machine.succeed("systemctl is-active sshd.service")

      # Verify SSH is listening
      machine.wait_for_open_port(22)
    '';
  };

  # Test that core packages are available on the system
  vm-packages = mkTest {
    name = "vm-test-packages";
    testScript = ''
      machine.wait_for_unit("multi-user.target")

      # Core packages from base.nix
      machine.succeed("which zsh")

      # Verify zsh actually works
      machine.succeed("zsh -c 'echo hello'")
    '';
  };
}
