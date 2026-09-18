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
  streamingModuleText = builtins.readFile ../modules/nixos/streaming.nix;
  caddyNixosModuleText = builtins.readFile ../modules/services/caddy/nixos.nix;

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

  # Test: zero should have hardware-specific packages for connected peripherals
  # Corsair H100i RGB PRO XT AIO (liquidctl), Razer Naga Trinity (openrazer + polychromatic),
  # IT8297 RGB controller (openrgb), NVMe drives (nvme-cli + smartmontools), AMD GPU
  # diagnostics (amdgpu_top + libva-utils + vulkan-tools), C920 webcam (v4l-utils),
  # and general hardware debug tools (pciutils + usbutils)
  zeroHardwarePackagesTest = let
    expectedPackages = [
      "liquidctl"
      "openrgb"
      "polychromatic"
      "nvme-cli"
      "smartmontools"
      "v4l-utils"
      "amdgpu_top"
      "libva-utils"
      "vulkan-tools"
      "pciutils"
      "usbutils"
    ];
    checkPkg = pkg:
      assertContainsStr "has ${pkg}" pkg zeroConfigText;
  in
    pkgs.runCommand "test-zero-hardware-packages"
    {}
    ''
      echo "=== Testing Zero hardware packages ==="

      ${lib.concatMapStringsSep "\n" checkPkg expectedPackages}
      ${assertContainsStr "openrazer block" "hardware.openrazer = {" zeroConfigText}
      ${assertContainsStr "openrazer enabled" "enable = true" zeroConfigText}
      ${assertContainsStr "openrazer users" ''"monkey"'' zeroConfigText}

      echo "Zero hardware packages test passed"
      touch $out
    '';
  # Test: zero is cloud-only (OpenCode Go, which falls back to OpenCode Zen) —
  # no local models, no legacy LLM endpoint declarations, and the OpenCode Go
  # API key wired through 1Password like on MegamanX.
  zeroCloudOnlyConfigTest =
    pkgs.runCommand "test-zero-cloud-only-config"
    {}
    ''
      echo "=== Testing Zero cloud-only LLM configuration ==="

      # Default model is a cloud model via the opencode-go provider
      ${assertContainsStr "cloud default model" "opencode-go/gpt-5.6-luna" zeroConfigText}
      # No local model targeting anywhere
      ${assertNotContainsStr "no local-bifrost" "local-bifrost" zeroConfigText}
      ${assertNotContainsStr "no local qwen model" "qwen3.8-27b" zeroConfigText}
      ${assertNotContainsStr "no omlx" "omlx" zeroConfigText}
      # Legacy llmEndpoints block removed
      ${assertNotContainsStr "no llmEndpoints" "llmEndpoints" zeroConfigText}
      # OpenCode Go API key wired through 1Password (same item as MegamanX)
      ${assertContainsStr "go 1password item" "op://Homelab/OpenCode Go API/credential" zeroConfigText}

      echo "Zero cloud-only config test passed"
      touch $out
    '';

  # Test: Sunshine pairing should be completable from a LAN phone or other
  # browser, while the web UI remains limited to LAN clients.
  zeroSunshineLanPairingTest =
    pkgs.runCommand "test-zero-sunshine-lan-pairing"
    {}
    ''
      echo "=== Testing Zero Sunshine LAN pairing ==="

      ${assertContainsStr "LAN PIN origin" ''origin_pin_allowed = "lan"'' streamingModuleText}
      ${assertContainsStr "LAN web UI origin" ''origin_web_ui_allowed = "lan"'' streamingModuleText}
      ${assertContainsStr "stable Sunshine name" "sunshine_name = config.networking.hostName" streamingModuleText}
      ${assertContainsStr "firewall enabled" "firewall.enable = true" zeroConfigText}

      echo "Zero Sunshine LAN pairing test passed"
      touch $out
    '';

  # Test: Sunshine's web password must come from opnix at runtime rather than
  # being embedded in the Nix-generated configuration.
  zeroSunshinePasswordSecretTest =
    pkgs.runCommand "test-zero-sunshine-password-secret"
    {}
    ''
      echo "=== Testing Zero Sunshine 1Password password ==="

      ${assertContainsStr "Sunshine password reference" "Sunshine/password" zeroConfigText}
      ${assertContainsStr "runtime secret path" "/run/secrets/sunshine-password" zeroConfigText}
      ${assertContainsStr "credential update hook" "--creds monkey" streamingModuleText}
      ${assertNotContainsStr "no plaintext password" "password =" streamingModuleText}

      echo "Zero Sunshine 1Password password test passed"
      touch $out
    '';

  # Test: Caddy should expose Sunshine's web UI through Cloudflare-backed
  # public HTTPS without attempting to proxy Moonlight's streaming protocols.
  zeroSunshineCaddyProxyTest =
    pkgs.runCommand "test-zero-sunshine-caddy-proxy"
    {}
    ''
      echo "=== Testing Zero Sunshine Caddy proxy ==="

      ${assertContainsStr "Caddy enabled" "caddy = {" zeroConfigText}
      ${assertContainsStr "Sunshine Caddy app" "apps.sunshine = {" zeroConfigText}
      ${assertContainsStr "public Sunshine hostname" "sunshine.buildingbananas.com" zeroConfigText}
      ${assertContainsStr "Cloudflare DNS challenge" "dns cloudflare {env.CLOUDFLARE_API_TOKEN}" caddyNixosModuleText}
      ${assertContainsStr "runtime Cloudflare secret" "/run/secrets/cloudflare-api-token" zeroConfigText}
      ${assertContainsStr "Cloudflare token reference" "cloudflare.com/dns-api-token" zeroConfigText}
      ${assertContainsStr "Cloudflare Caddy plugin" "caddy-dns/cloudflare@v0.2.4" caddyNixosModuleText}
      ${assertContainsStr "Caddy secret path option" "cloudflareApiTokenPath" caddyNixosModuleText}
      ${assertContainsStr "LAN proxy restriction" "remote_ip 10.0.0.0/8" caddyNixosModuleText}
      ${assertContainsStr "Sunshine upstream TLS override" "upstreamTlsSkipVerify = true" zeroConfigText}
      ${assertContainsStr "Sunshine secret readiness wait" "for attempt in" streamingModuleText}
      ${assertContainsStr "HTTPS Sunshine upstream" "https://127.0.0.1:47990" zeroConfigText}
      ${assertContainsStr "Caddy virtual hosts" "virtualHosts = mapAttrs'" caddyNixosModuleText}
      ${assertContainsStr "Caddy firewall" "allowedTCPPorts = [80 443]" caddyNixosModuleText}

      echo "Zero Sunshine Caddy proxy test passed"
      touch $out
    '';
}
