# Zero target configuration tests
# Tests that the tailscale-autoconnect service uses opnix secrets
# instead of the fragile TAILSCALE_AUTH_KEY environment variable
#
# Uses builtins.readFile + Nix string operations to check file content
# without requiring derivation builds or shell grep commands.
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Read zero config as a string for pattern checking (pure Nix, no derivation needed)
  zeroConfigText = builtins.readFile ../targets/zero/default.nix;

  # Helper: check if string contains substring, throw if not
  assertContainsStr = name: needle: haystack:
    if lib.hasInfix needle haystack
    then ''echo "  ${name}: OK"''
    else throw "${name}: '${needle}' not found in zero config";

  # Helper: check if string does NOT contain substring, throw if found
  assertNotContainsStr = name: needle: haystack:
    if !(lib.hasInfix needle haystack)
    then ''echo "  ${name}: OK"''
    else throw "${name}: '${needle}' should not be in zero config";

  # Helper: check substring occurs at least N times, throw if not.
  # builtins.split returns a list of length (2 * occurrences + 1).
  assertOccursAtLeast = name: count: needle: haystack:
    if (builtins.length (builtins.split needle haystack) > (count * 2))
    then ''echo "  ${name}: OK"''
    else throw "${name}: '${needle}' should occur at least ${toString count} times in zero config";
in {
  # Test: zero config should set defaultVault and override authKeyOpnixItem
  zeroTailscaleSecretConfigTest =
    pkgs.runCommand "test-zero-tailscale-secret-config"
    {}
    ''
      echo "=== Testing Zero Tailscale opnix secret config ==="

      ${assertContainsStr "default vault" ''"Homelab"'' zeroConfigText}
      ${assertContainsStr "auth key item" "Tailscale Auth Key/credential" zeroConfigText}

      echo "Tailscale opnix secret config test passed"
      touch $out
    '';

  # Test: the gaming module should disable SDL's HIDAPI joystick driver for
  # Steam so xpadneo Bluetooth controllers work. Steam/SDL2 reads Xbox
  # Bluetooth controllers over hidraw via the SDL_JOYSTICK_HIDAPI driver,
  # which produces wrong/absent SDL mappings for xpadneo devices — Steam
  # detects the controller (jstest works) but games receive no input.
  # xpadneo's documented workaround is to export SDL_JOYSTICK_HIDAPI=0.
  zeroSteamSdlHidapiEnvTest = let
    gamingModuleText = builtins.readFile ../modules/nixos/gaming.nix;
  in
    pkgs.runCommand "test-zero-steam-sdl-hidapi-env"
    {}
    ''
      echo "=== Testing Steam SDL HIDAPI disabled for xpadneo ==="

      ${assertContainsStr "steam package override" "SDL_JOYSTICK_HIDAPI" gamingModuleText}
      ${assertContainsStr "hidapi disabled" ''"0"'' gamingModuleText}
      ${assertOccursAtLeast "both package and gamescope session" 2 "SDL_JOYSTICK_HIDAPI = \"0\";" gamingModuleText}

      echo "Steam SDL HIDAPI env test passed"
      touch $out
    '';

  # Test: tailscale-autoconnect service should depend on onepassword-secrets
  # Read the tailscale role module since that's where the service is defined
  zeroTailscaleOpnixDepTest = let
    tailscaleModuleText = builtins.readFile ../modules/roles/tailscale.nix;
  in
    pkgs.runCommand "test-zero-tailscale-opnix-dep"
    {}
    ''
      echo "=== Testing Zero Tailscale opnix dependency ==="

      ${assertContainsStr "onepassword-secrets dep" "onepassword-secrets.service" tailscaleModuleText}
      ${assertContainsStr "tailscale auth key name" "tailscale-auth-key" tailscaleModuleText}

      echo "Tailscale opnix dependency test passed"
      touch $out
    '';

  # Test: tailscale-autoconnect service should NOT reference TAILSCALE_AUTH_KEY env var
  zeroTailscaleNoEnvVarTest = let
    tailscaleModuleText = builtins.readFile ../modules/roles/tailscale.nix;
  in
    pkgs.runCommand "test-zero-tailscale-no-env-var"
    {}
    ''
      echo "=== Testing Zero Tailscale no env var ==="

      ${assertNotContainsStr "no TAILSCALE_AUTH_KEY" "TAILSCALE_AUTH_KEY" tailscaleModuleText}

      echo "Tailscale no env var test passed"
      touch $out
    '';

  # Test: tailscale-autoconnect service should reference opnix secrets file
  zeroTailscaleSecretFileTest = let
    tailscaleModuleText = builtins.readFile ../modules/roles/tailscale.nix;
  in
    pkgs.runCommand "test-zero-tailscale-secret-file"
    {}
    ''
      echo "=== Testing Zero Tailscale secret file reference ==="

      ${assertContainsStr "secret file path" "/run/secrets/tailscale-auth-key" tailscaleModuleText}

      echo "Tailscale secret file reference test passed"
      touch $out
    '';

  # Test: tailscale-autoconnect service should fail loudly (exit 1) if key missing
  # This checks that the old "Warning: TAILSCALE_AUTH_KEY not set" silent-skip is gone
  # and replaced with an explicit error and exit 1
  zeroTailscaleFailLoudTest = let
    tailscaleModuleText = builtins.readFile ../modules/roles/tailscale.nix;
  in
    pkgs.runCommand "test-zero-tailscale-fail-loud"
    {}
    ''
      echo "=== Testing Zero Tailscale fails loudly if key missing ==="

      ${assertNotContainsStr "no silent warning" "Warning: TAILSCALE_AUTH_KEY not set" tailscaleModuleText}
      ${assertContainsStr "exit 1 present" "exit 1" tailscaleModuleText}

      echo "Tailscale fail-loud test passed"
      touch $out
    '';
}
