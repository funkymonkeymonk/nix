{
  pkgs,
  self,
  ...
}: let
  hasConfig = name: builtins.hasAttr name self.nixosConfigurations;
  hasTargetModule = name: builtins.pathExists (../targets + "/${name}/default.nix");
  flakeText = builtins.readFile ../flake.nix;

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
      if builtins.pathExists ../library/machines/cattle.nix
      then ''echo "  cattle machine module: defined ✓"''
      else ''echo "FAIL: cattle machine module not found"; exit 1''
    }

    ${
      if pkgs.lib.hasInfix "./library/machines/cattle.nix" flakeText
      then ""
      else ''echo "FAIL: cattle machine module not imported by flake.nix"; exit 1''
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
  inherit phase2CattleTest;
}
