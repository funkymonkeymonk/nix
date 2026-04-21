# Workspace-aware switch shell function tests
# Tests the jj-workspace-lib shared library using mock filesystem structures.
# These are bash-based tests (not evalModules) since the logic is shell, not Nix.
{pkgs, ...}: {
  # Test the workspace detection library and shell function setup
  workspaceSwitchTest =
    pkgs.runCommand "test-workspace-switch"
    {
      # Pass the library and test script into the build environment
      src = ../modules/common/scripts/jj-workspace-lib;
      testScript = ./test-workspace-switch.sh;
      nativeBuildInputs = [pkgs.bash];
    }
    ''
      echo "=== Testing Workspace-Aware Switch Functions ==="

      # Set up SCRIPT_DIR so the test can find the library
      export SCRIPT_DIR=$(mktemp -d)
      mkdir -p "$SCRIPT_DIR/modules/common/scripts"
      cp "$src" "$SCRIPT_DIR/modules/common/scripts/jj-workspace-lib"

      # Run the tests
      bash "$testScript"

      touch $out
    '';
}
