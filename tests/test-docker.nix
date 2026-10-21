# Tests shared NixOS Docker configuration and configured-user access.
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  dockerConfig =
    (lib.evalModules {
      modules =
        stubs.base
        ++ stubs.nixosServices
        ++ [
          {
            options.system.autoUpgrade = lib.mkOption {
              type = lib.types.anything;
              default = {};
            };
            options.virtualisation = lib.mkOption {
              type = lib.types.anything;
              default = {};
            };
            config.myConfig.users = [
              {
                name = "monkey";
                email = "monkey@example.com";
                fullName = "Monkey";
                isAdmin = true;
                sshIncludes = [];
              }
              {
                name = "secondary";
                email = "secondary@example.com";
                fullName = "Secondary User";
                isAdmin = false;
                sshIncludes = [];
              }
            ];
          }
          ../modules/nixos/base.nix
        ];
    })
    .config;

  hasDockerGroup = user: builtins.elem "docker" dockerConfig.users.users.${user}.extraGroups;
  retainsBaseGroups = user:
    builtins.all
    (group: builtins.elem group dockerConfig.users.users.${user}.extraGroups)
    ["networkmanager" "wheel" "onepassword-secrets"];
in {
  dockerNixosConfigTest = pkgs.runCommand "test-nixos-docker-config" {} ''
    echo "=== Testing shared NixOS Docker configuration ==="

    ${
      if dockerConfig.virtualisation.docker.enable or false
      then ''echo "  Docker daemon enabled: OK"''
      else ''echo "  Docker daemon should be enabled"; exit 1''
    }

    ${
      if hasDockerGroup "monkey" && hasDockerGroup "secondary"
      then ''echo "  All configured users are in the docker group: OK"''
      else ''echo "  Configured users must be in the docker group"; exit 1''
    }

    ${
      if retainsBaseGroups "monkey" && retainsBaseGroups "secondary"
      then ''echo "  Existing user groups are preserved: OK"''
      else ''echo "  Existing user groups must be preserved"; exit 1''
    }

    touch $out
  '';
}
