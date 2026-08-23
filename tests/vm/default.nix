# NixOS VM integration tests
# These tests boot a minimal NixOS VM and verify system behavior.
# Only runs on x86_64-linux (NixOS testing framework requirement).
{pkgs, ...}: let
  lib = pkgs.lib;

  # Helper to create a NixOS test with our modules
  mkTest = {
    name,
    testScript,
    extraModules ? [],
    roles ? {},
  }:
    pkgs.testers.nixosTest {
      inherit name;
      nodes.machine = {lib, ...}: {
        imports =
          [
            ../../modules/common/options.nix
            ../../modules/common/cachix.nix
            ../../modules/common/llm-client.nix
            ../../modules/common/onepassword.nix
            ../../modules/common/shell.nix
            ../../modules/common/users.nix
            ../../modules/common/zellij.nix
            ../../modules/common/obsidian.nix
            ../../modules/common/charm.nix
            ../../modules/common/syncthing.nix
            ../../modules/common/motd.nix
            ../../modules/common/agent-user.nix
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
            onepassword.enable = lib.mkForce false;
            inherit roles;
          };

          # Minimal VM config
          system.stateVersion = "25.05";
          virtualisation.memorySize = 1024;
        };
      };
      inherit testScript;
    };

  # Generic per-role VM package test generator.
  #
  # Boots the exact same NixOS node mkTest always boots (mkTest is the
  # single source of truth for the module list -- called here, not
  # duplicated), enabling only the given role. The resulting node's
  # environment.systemPackages is introspected to derive the binary each
  # package actually provides (meta.mainProgram, falling back to
  # pname/name), and every resolved binary is presence-checked on the
  # booted VM via `command -v` -- presence-only, never actually run --
  # which previously risked hanging on GUI/Electron packages (e.g. logseq).
  #
  # `nodes.machine` on a nixosTest derivation exposes the fully evaluated
  # NixOS config for that node (see nixpkgs' nixos/lib/testing/nodes.nix),
  # so introspecting it is pure evaluation -- no VM is booted just to
  # compute the binaries list.
  mkRoleVmTest = role: let
    roles = {${role}.enable = true;};
    introspected = mkTest {
      name = "vm-role-${role}-introspect";
      inherit roles;
      testScript = "";
    };
    binaries =
      map (pkg: pkg.meta.mainProgram or pkg.pname or pkg.name)
      introspected.nodes.machine.environment.systemPackages;
  in
    mkTest {
      name = "vm-role-${role}";
      inherit roles;
      testScript =
        ''
          machine.wait_for_unit("multi-user.target")
        ''
        + lib.concatMapStringsSep "\n" (
          b: ''machine.succeed("command -v ${lib.escapeShellArg b}")''
        )
        binaries;
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

  # Boot-test the foundation role's actual environment.systemPackages.
  # Foundation defaults to enable=true and runs on every host in the fleet
  # (all 5 NixOS targets) -- this is the one role every machine depends on,
  # and until now it had never been boot-tested.
  vm-role-foundation = mkRoleVmTest "foundation";

  # Boot-test the developer role's actual environment.systemPackages.
  vm-role-developer = mkRoleVmTest "developer";
}
