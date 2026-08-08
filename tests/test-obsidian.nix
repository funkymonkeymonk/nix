# Obsidian option tests
# Validates option defaults and custom values from modules/common/obsidian.nix
{pkgs, ...}: let
  inherit (pkgs) lib;

  stubs = import ./stubs.nix {inherit pkgs;};

  obsidianDefaults =
    (lib.evalModules {
      modules = stubs.base;
    }).config.myConfig.obsidian;

  obsidianCustom =
    (lib.evalModules {
      modules =
        stubs.base
        ++ [
          {
            config.myConfig.obsidian = {
              enable = true;
              vaultRoot = "/tmp/vaults";
              vaults = ["personal" "work"];
              syncAllVaults = true;
              allVaults = ["personal" "work" "archive"];
            };
          }
        ];
    }).config.myConfig.obsidian;
in {
  obsidianOptionsTest = pkgs.runCommand "test-obsidian-options" {} ''
    echo "=== Testing Obsidian Option Defaults ==="

    ${
      if !obsidianDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if obsidianDefaults.vaultRoot == "~/Documents/vaults"
      then ''echo "  vaultRoot default = ~/Documents/vaults: OK"''
      else ''echo "  vaultRoot should default to ~/Documents/vaults!"; exit 1''
    }

    ${
      if obsidianDefaults.vaults == []
      then ''echo "  vaults default = []: OK"''
      else ''echo "  vaults should default to []!"; exit 1''
    }

    ${
      if !obsidianDefaults.syncAllVaults
      then ''echo "  syncAllVaults default = false: OK"''
      else ''echo "  syncAllVaults should default to false!"; exit 1''
    }

    ${
      if obsidianDefaults.allVaults == []
      then ''echo "  allVaults default = []: OK"''
      else ''echo "  allVaults should default to []!"; exit 1''
    }

    echo "All Obsidian option defaults verified"
    touch $out
  '';

  obsidianCustomOptionsTest = pkgs.runCommand "test-obsidian-custom-options" {} ''
    echo "=== Testing Obsidian Custom Options ==="

    ${
      if obsidianCustom.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if obsidianCustom.vaultRoot == "/tmp/vaults"
      then ''echo "  vaultRoot = /tmp/vaults: OK"''
      else ''echo "  vaultRoot should be /tmp/vaults!"; exit 1''
    }

    ${
      if obsidianCustom.vaults == ["personal" "work"]
      then ''echo "  vaults = [\"personal\" \"work\"]: OK"''
      else ''echo "  vaults should be [\"personal\" \"work\"]!"; exit 1''
    }

    ${
      if obsidianCustom.syncAllVaults
      then ''echo "  syncAllVaults = true: OK"''
      else ''echo "  syncAllVaults should be true!"; exit 1''
    }

    ${
      if obsidianCustom.allVaults == ["personal" "work" "archive"]
      then ''echo "  allVaults = [\"personal\" \"work\" \"archive\"]: OK"''
      else ''echo "  allVaults should be [\"personal\" \"work\" \"archive\"]!"; exit 1''
    }

    echo "All Obsidian custom options verified"
    touch $out
  '';
}
