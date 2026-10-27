{
  pkgs,
  self,
  inputs,
  ...
}: let
  inherit (pkgs) lib;
  hasConfig = name: builtins.hasAttr name self.nixosConfigurations;
  catalog = import ../library/machines/catalog.nix {inherit inputs;};

  phase3ZeroTest = pkgs.runCommand "test-phase3-zero" {} ''
    echo "=== Testing Zero NixOS Config ==="
    echo ""

    # Test zero config exists and uses the new archetype-based composition.
    ${
      if hasConfig "zero"
      then ""
      else ''echo "FAIL: zero not found"; exit 1''
    }
    echo "  zero: defined ✓"

    # The old zero-v2 scratch output has been retired (Phase 8 cleanup).
    ${
      if hasConfig "zero-v2"
      then ''echo "FAIL: zero-v2 should be retired"; exit 1''
      else ""
    }
    echo "  zero-v2: retired ✓"

    echo ""
    echo "All zero tests passed"
    touch $out
  '';

  # Structural regression guard for the catalog projection: zero is declared
  # once in the machine catalog and projected into the native flake output.
  flakeText = builtins.readFile ../flake.nix;
  machineProjectionText = builtins.readFile ../library/machines/flake-parts.nix;
  zero = catalog.zero;
  expectedZeroModules = [
    ../library/archetypes/desktop-nixos.nix
    ../modules/nixos/base.nix
    ../modules/nixos/desktop.nix
    ../modules/nixos/gaming.nix
    ../modules/nixos/streaming.nix
    ../modules/services/caddy/nixos.nix
    ../os/nixos.nix
    ../disk-configs/zero.nix
    ../library/archetypes/desktop-machine.nix
    ../modules/nixos/ghostty-terminfo.nix
    ../targets/zero
  ];

  phase3ZeroFlakePartsTest = pkgs.runCommand "test-phase3-zero-flake-parts" {} ''
    echo "=== Testing Zero is projected from the canonical machine catalog ==="

    ${
      if zero.kind == "nixos" && zero.system == "x86_64-linux" && zero.hostname == "zero"
      then ''echo "  zero catalog platform and hostname: OK"''
      else ''echo "  FAIL: zero catalog record has unexpected platform or hostname"; exit 1''
    }

    ${
      if zero.secretProfile == "Homelab"
      then ''echo "  zero Homelab profile: OK"''
      else ''echo "  FAIL: zero should retain its Homelab profile"; exit 1''
    }

    ${
      if zero.modules == expectedZeroModules
      then ''echo "  zero module stack: OK"''
      else ''echo "  FAIL: zero catalog module stack changed"; exit 1''
    }

    ${
      if zero.overrides.autoUpgrade.flakeUrl == "github:funkymonkeymonk/nix#zero"
      then ''echo "  zero auto-upgrade override: OK"''
      else ''echo "  FAIL: zero auto-upgrade override is missing"; exit 1''
    }

    ${
      if !(lib.hasInfix "\"zero\" = libraryLib.mkNixosSystem" flakeText)
      then ''echo "  flake.nix no longer defines zero inline: OK"''
      else ''echo "  FAIL: flake.nix should not define zero inline anymore"; exit 1''
    }

    ${
      if lib.hasInfix "flake-parts.lib.mkFlake" flakeText
      then ''echo "  flake.nix uses flake-parts.lib.mkFlake: OK"''
      else ''echo "  FAIL: flake.nix should use flake-parts.lib.mkFlake"; exit 1''
    }

    ${
      if
        lib.hasInfix "catalog = import ./catalog.nix" machineProjectionText
        && lib.hasInfix "flake.nixosConfigurations = lib.mapAttrs mkNixos nixosMachines" machineProjectionText
      then ''echo "  flake-parts projects catalog NixOS machines: OK"''
      else ''echo "  FAIL: flake-parts must project NixOS systems from the catalog"; exit 1''
    }

    ${
      if
        !(lib.hasInfix "library/machines/zero.nix" flakeText)
        && !(lib.hasInfix "machines/zero.nix" machineProjectionText)
      then ''echo "  legacy per-machine zero.nix is not required: OK"''
      else ''echo "  FAIL: catalog projection still depends on per-machine zero.nix"; exit 1''
    }

    ${
      if self.nixosConfigurations.zero.config.networking.hostName == "zero"
      then ''echo "  generated nixosConfigurations.zero: OK"''
      else ''echo "  FAIL: catalog projection should generate nixosConfigurations.zero"; exit 1''
    }

    echo "All zero catalog projection tests passed"
    touch $out
  '';
in {
  inherit phase3ZeroTest phase3ZeroFlakePartsTest;
}
