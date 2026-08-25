{
  pkgs,
  self,
  ...
}: let
  inherit (pkgs) lib;
  hasConfig = name: builtins.hasAttr name self.nixosConfigurations;

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

  # Structural regression guard for the flake-parts pilot migration: zero
  # must be defined via library/machines/zero.nix, not inline in flake.nix.
  flakeText = builtins.readFile ../flake.nix;

  phase3ZeroFlakePartsTest = pkgs.runCommand "test-phase3-zero-flake-parts" {} ''
    echo "=== Testing Zero is wired via flake-parts, not inline in flake.nix ==="

    ${
      if builtins.pathExists ../library/machines/zero.nix
      then ''echo "  library/machines/zero.nix exists: OK"''
      else ''echo "  FAIL: library/machines/zero.nix should exist"; exit 1''
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
      if lib.hasInfix "./library/machines/zero.nix" flakeText
      then ''echo "  flake.nix imports library/machines/zero.nix: OK"''
      else ''echo "  FAIL: flake.nix should import library/machines/zero.nix"; exit 1''
    }

    echo "All zero flake-parts structural tests passed"
    touch $out
  '';
in {
  inherit phase3ZeroTest phase3ZeroFlakePartsTest;
}
