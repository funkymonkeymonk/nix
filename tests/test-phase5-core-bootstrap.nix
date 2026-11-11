{
  pkgs,
  self,
  inputs,
  ...
}: let
  inherit (pkgs) lib;
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  machineProjectionText = builtins.readFile ../library/machines/flake-parts.nix;
  machineConfigurationsText = builtins.readFile ../library/machines/flake-configurations.nix;
  bootstrap = catalog.bootstrap;
  installerIso = catalog."installer-iso";
  expectedBootstrapModules = [
    ../modules/common/core.nix
    ../targets/bootstrap
    ../modules/common/options.nix
  ];
  expectedInstallerIsoModules = [
    ../targets/installer-iso/default.nix
  ];
in {
  coreBootstrapTest = pkgs.runCommand "test-core-bootstrap" {} ''
    echo "=== Testing bootstrap catalog projection ==="
    echo ""

    ${
      if
        bootstrap.kind
        == "nixos"
        && bootstrap.system == "x86_64-linux"
        && bootstrap.secretProfile == "Personal"
        && bootstrap.builder == "nixos"
        && bootstrap.hostname == null
        && bootstrap.modules == expectedBootstrapModules
      then ''echo "  bootstrap catalog record and module stack: OK"''
      else ''echo "FAIL: bootstrap catalog record or module stack changed"; exit 1''
    }

    ${
      if
        installerIso.kind
        == "nixos"
        && installerIso.system == "x86_64-linux"
        && installerIso.secretProfile == "Personal"
        && installerIso.builder == "nixos"
        && installerIso.hostname == null
        && installerIso.modules == expectedInstallerIsoModules
      then ''echo "  installer-iso catalog record and module stack: OK"''
      else ''echo "FAIL: installer-iso catalog record or module stack changed"; exit 1''
    }

    ${
      if
        lib.hasInfix "import ./flake-configurations.nix {\n  inherit inputs libraryLib;\n  catalog = import ./catalog.nix {inherit inputs;};\n}" machineProjectionText
        && lib.hasInfix "flake.nixosConfigurations = lib.mapAttrs mkNixos nixosMachines" machineConfigurationsText
        && lib.hasInfix "flake.darwinConfigurations = lib.mapAttrs mkDarwin darwinMachines" machineConfigurationsText
      then ''echo "  flake-parts delegates canonical catalog projections to the shared helper: OK"''
      else ''echo "FAIL: shared configuration helper does not project NixOS and Darwin outputs from the canonical catalog"; exit 1''
    }

    ${
      if
        builtins.hasAttr "bootstrap" self.nixosConfigurations
        && builtins.hasAttr "installer-iso" self.nixosConfigurations
      then ''echo "  bootstrap and installer-iso NixOS configurations: OK"''
      else ''echo "FAIL: catalog projection did not generate bootstrap and installer-iso"; exit 1''
    }

    echo "All bootstrap catalog projection tests passed"
    touch $out
  '';
}
