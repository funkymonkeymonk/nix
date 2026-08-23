# Sketchybar removal regression test
#
# The sketchybar home-manager module was removed (never enabled on any
# host, no chosen feature direction, and known bugs from closed PR #280:
# missing shebang in sketchybarrc, require() path issues from writing
# each Lua file as a separate pkgs.writeText store path).
#
# This test asserts the module, its options, its plumbing, and the dead
# aerospace-sketchybar flake input stay gone. It uses builtins.readFile +
# pure Nix string checks (no derivation builds, no shell grep) so it's
# fast and pure-eval-safe.
{pkgs, ...}: let
  inherit (pkgs) lib;

  optionsText = builtins.readFile ../modules/common/options.nix;
  usersText = builtins.readFile ../modules/common/users.nix;
  themesText = builtins.readFile ../modules/home-manager/themes.nix;
  flakeText = builtins.readFile ../flake.nix;
  devenvText = builtins.readFile ../devenv.nix;
  testCoverageText = builtins.readFile ../tests/test-coverage.nix;

  assertNotContainsStr = name: needle: haystack:
    if !(lib.hasInfix needle haystack)
    then ''echo "  ${name}: OK"''
    else throw "${name}: '${needle}' should not be present (sketchybar module was removed)";

  assertPathMissing = name: path:
    if !(builtins.pathExists path)
    then ''echo "  ${name}: OK"''
    else throw "${name}: '${toString path}' should not exist (sketchybar module was removed)";
in {
  sketchybarModuleRemovedTest =
    pkgs.runCommand "test-sketchybar-module-removed"
    {}
    ''
      echo "=== Testing sketchybar module directory is gone ==="

      ${assertPathMissing "module dir" ../modules/home-manager/sketchybar}

      echo "sketchybar module removal test passed"
      touch $out
    '';

  sketchybarOptionsRemovedTest =
    pkgs.runCommand "test-sketchybar-options-removed"
    {}
    ''
      echo "=== Testing myConfig.sketchybar options are gone ==="

      ${assertNotContainsStr "options.nix" "sketchybar" optionsText}

      echo "sketchybar options removal test passed"
      touch $out
    '';

  sketchybarWiringRemovedTest =
    pkgs.runCommand "test-sketchybar-wiring-removed"
    {}
    ''
      echo "=== Testing sketchybar plumbing is gone from users.nix, themes.nix, flake.nix, devenv.nix ==="

      ${assertNotContainsStr "users.nix import" "sketchybar" usersText}
      ${assertNotContainsStr "themes.nix theme" "sketchybar" themesText}
      ${assertNotContainsStr "flake.nix aerospace-sketchybar input" "aerospace-sketchybar" flakeText}
      ${assertNotContainsStr "flake.nix old sketchybar-theme check" "sketchybar-theme" flakeText}
      ${assertNotContainsStr "flake.nix old sketchybar-entrypoint check" "sketchybar-entrypoint" flakeText}
      ${assertNotContainsStr "devenv.nix test:sketchybar task" "test:sketchybar" devenvText}
      ${assertNotContainsStr "tests/test-coverage.nix sketchybar entry" "sketchybar" testCoverageText}

      echo "sketchybar wiring removal test passed"
      touch $out
    '';
}
