# Zero machine configuration tests
# Tests that Tailscale enrollment uses deployment-generated OAuth auth keys.
#
# Uses builtins.readFile + Nix string operations to check file content
# without requiring derivation builds or shell grep commands.
{
  pkgs,
  self ? null,
  ...
}: let
  inherit (pkgs) lib;

  # Read zero config as a string for pattern checking (pure Nix, no derivation needed)
  zeroConfigText = builtins.readFile ../machines/zero/default.nix;
  streamingModuleText = builtins.readFile ../modules/nixos/streaming.nix;
  caddyNixosModuleText = builtins.readFile ../modules/services/caddy/nixos.nix;
  backupNixosModuleText = builtins.readFile ../modules/nixos/backup.nix;

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
  # Zero does not own the media-center configuration; drlight selects that behavior.
  zeroNoMediaConfigTest =
    if self == null
    then
      pkgs.runCommand "test-zero-media-config-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else let
      zero = self.nixosConfigurations.zero.config;
    in
      pkgs.runCommand "test-zero-media-config" {} ''
        echo "=== Evaluating Zero media configuration ownership ==="
        ${
          if !(zero.myConfig.mediaConfig.enable or false)
          then ''echo "Zero does not enable drlight media configuration: OK"''
          else ''echo "FAIL: Zero must not enable drlight media configuration"; exit 1''
        }
        touch $out
      '';

  # Home Manager secrets stored under Zero's home must be owned by the user.
  zeroHomeManagerSecretOwnershipTest =
    if self == null
    then
      pkgs.runCommand "test-zero-home-secret-ownership-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else let
      secrets = builtins.attrValues self.nixosConfigurations.zero.config.home-manager.users.monkey.programs.onepassword-secrets.secrets;
      expectedPaths = [
        ".config/opencode/secrets/megamanx-bifrost-apikey"
        ".pi/agent/secrets/opencode-go-apikey"
        ".pi/agent/secrets/typesafe_api_key"
      ];
      ownershipCorrect =
        builtins.all (
          expectedPath:
            lib.any (
              secret:
                secret.path
                == expectedPath
                && secret.owner == "monkey"
                && secret.group == "users"
            )
            secrets
        )
        expectedPaths;
    in
      pkgs.runCommand "test-zero-home-secret-ownership" {} ''
        echo "=== Testing Zero Home Manager secret ownership ==="
        ${
          if ownershipCorrect
          then ''echo "All configured Home Manager secrets are owned by monkey:users: OK"''
          else ''echo "FAIL: Home Manager secrets under Zero's home must be owned by monkey:users"; exit 1''
        }
        touch $out
      '';

  # Test: Zero is no longer a Tailscale-enabled machine and has no static key.
  zeroTailscaleOAuthConfigTest =
    if self == null
    then
      pkgs.runCommand "test-zero-tailscale-oauth-config-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else let
      zero = self.nixosConfigurations.zero.config;
    in
      pkgs.runCommand "test-zero-tailscale-oauth-config" {} ''
        echo "=== Testing Zero Tailscale OAuth configuration ==="
        ${
          if !(zero.myConfig.tailscale.enable or false)
          then ''echo "Zero is Tailscale-disabled: OK"''
          else ''echo "FAIL: Zero must be Tailscale-disabled"; exit 1''
        }
        ${
          if !(zero.myConfig.tailscale ? authKeyOpnixItem) && !(zero.myConfig.tailscale ? authKeyMode) && !(zero.myConfig.onepassword.secrets ? tailscaleAuthKey)
          then ''echo "Zero has no static Tailscale auth-key configuration: OK"''
          else ''echo "FAIL: Zero must not configure a static Tailscale auth key"; exit 1''
        }
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

  # Test: Tailscale auto-connect consumes the temporary deployment auth-key
  # file and has no dependency on the static Opnix auth-key secret.
  zeroTailscaleNoOpnixDepTest = let
    tailscaleRoleText = builtins.readFile ../modules/roles/tailscale.nix;
    tailscaleNixosText = builtins.readFile ../modules/nixos/tailscale.nix;
  in
    pkgs.runCommand "test-zero-tailscale-no-opnix-dep"
    {}
    ''
      echo "=== Testing Zero Tailscale deployment-key dependency ==="

      ${assertNotContainsStr "no static opnix service dependency" "opnix-secrets.service" tailscaleRoleText}
      ${assertContainsStr "deployment auth key file" "/run/devenv/tailscale-auth-key" tailscaleNixosText}

      echo "Tailscale deployment-key dependency test passed"
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
    tailscaleModuleText = builtins.readFile ../modules/nixos/tailscale.nix;
  in
    pkgs.runCommand "test-zero-tailscale-secret-file"
    {}
    ''
      echo "=== Testing Zero Tailscale secret file reference ==="

      ${assertContainsStr "deployment secret file path" "/run/devenv/tailscale-auth-key" tailscaleModuleText}

      echo "Tailscale secret file reference test passed"
      touch $out
    '';

  # Test: missing deployment keys must not trigger an interactive/static-key
  # fallback; an explicit deployment provides the one-time auth key.
  zeroTailscaleMissingOAuthKeyTest = let
    tailscaleRoleText = builtins.readFile ../modules/roles/tailscale.nix;
    tailscaleNixosText = builtins.readFile ../modules/nixos/tailscale.nix;
  in
    pkgs.runCommand "test-zero-tailscale-missing-oauth-key"
    {}
    ''
      echo "=== Testing Zero Tailscale missing OAuth key behavior ==="

      ${assertNotContainsStr "no static auth-key fallback" "authKeyOpnixItem" tailscaleRoleText}
      ${assertNotContainsStr "no environment auth-key fallback" "TAILSCALE_AUTH_KEY" tailscaleRoleText}
      ${assertContainsStr "deployment auth key message" "deployment auth key" tailscaleNixosText}

      echo "Tailscale missing OAuth key test passed"
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
  # Test: OpenCode uses MegamanX Bifrost by default while Pi keeps its direct Go provider.
  zeroCloudOnlyConfigTest =
    pkgs.runCommand "test-zero-cloud-only-config"
    {}
    ''
      echo "=== Testing Zero cloud-default LLM configuration ==="

      # OpenCode uses GPT-6 Luna through the MegamanX Bifrost provider.
      ${assertContainsStr "Bifrost cloud default model" ''model = "megamanx-bifrost/opencode-go/gpt-6-luna"'' zeroConfigText}
      ${assertContainsStr "Bifrost provider package" ''package = "@opencode/ai/providers/openai-compatible"'' zeroConfigText}
      ${assertContainsStr "MegamanX Bifrost endpoint" ''baseURL = "http://megamanx:8081/v1"'' zeroConfigText}
      ${assertContainsStr "Zero-specific Bifrost credential" ''onePasswordItem = "Bifrost Zero API Key/credential"'' zeroConfigText}
      ${assertNotContainsStr "OpenCode does not use its direct Go key" ''onePasswordItem = "OpenCode Service Account - Zero/credential"'' zeroConfigText}
      ${assertNotContainsStr "Pi does not pin the old global model" ''defaultModel = "gpt-5.6-luna"'' zeroConfigText}
      # Zero does not host a local oMLX inference service.
      ${assertNotContainsStr "no local omlx service" "omlx.enable = true" zeroConfigText}
      # Legacy llmEndpoints block removed
      ${assertNotContainsStr "no llmEndpoints" "llmEndpoints" zeroConfigText}
      # Pi keeps the Go service-account key wired through 1Password.
      ${assertContainsStr "Pi Go service-account item" ''opencodeGoOnePasswordItem = "OpenCode Service Account - Zero/credential"'' zeroConfigText}

      echo "Zero cloud-only config test passed"
      touch $out
    '';

  # Test: zero uses Pi's native OpenCode Go provider with a service-account key.
  zeroPiProviderPackageTest =
    pkgs.runCommand "test-zero-pi-provider-config"
    {}
    ''
      echo "=== Testing Zero Pi OpenCode provider config ==="

      ${assertNotContainsStr "no OAuth provider package" "pi-provider-opencode-console" zeroConfigText}
      ${assertContainsStr "native Go provider" ''defaultProvider = "opencode-go"'' zeroConfigText}
      ${assertContainsStr "Go service-account key" "OpenCode Service Account - Zero/credential" zeroConfigText}
      ${assertContainsStr "Pi explicitly opts into Go" ''opencodeGoOnePasswordItem = "OpenCode Service Account - Zero/credential"'' zeroConfigText}
      ${assertContainsStr "Pi Jev uses the same service account" ''jevOnePasswordItem = "OpenCode Service Account - Zero/credential"'' zeroConfigText}

      echo "Zero Pi OpenCode provider config test passed"
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
      ${assertContainsStr "KMS capture" ''capture = "kms"'' streamingModuleText}
      ${assertContainsStr "Steam Big Picture app" ''name = "Steam Big Picture"'' streamingModuleText}
      ${assertContainsStr "Desktop app" ''name = "Desktop"'' streamingModuleText}
      ${assertContainsStr "Sunshine CSRF origin" ''csrf_allowed_origins = "https://sunshine.home.buildingbananas.com"'' streamingModuleText}
      ${assertContainsStr "stable Sunshine name" "sunshine_name = config.networking.hostName" streamingModuleText}
      ${assertContainsStr "firewall enabled" "firewall.enable = true" zeroConfigText}

      echo "Zero Sunshine LAN pairing test passed"
      touch $out
    '';

  # Test: changes to the NixOS-managed Sunshine user unit are propagated to
  # the logged-in user's systemd manager during a system switch.
  zeroSunshineUserRestartTest =
    pkgs.runCommand "test-zero-sunshine-user-restart"
    {}
    ''
      echo "=== Testing Sunshine user service restart bridge ==="

      ${assertContainsStr "user manager reload" "--user daemon-reload" streamingModuleText}
      ${assertContainsStr "Sunshine restart" "--user restart sunshine.service" streamingModuleText}
      ${assertContainsStr "graphical session guard" "is-active --quiet graphical-session.target" streamingModuleText}
      ${assertContainsStr "restart trigger" "restartTriggers" streamingModuleText}
      ${assertContainsStr "persistent oneshot" "RemainAfterExit = true" streamingModuleText}

      echo "Sunshine user service restart bridge test passed"
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
      ${assertContainsStr "runtime secret path" "/var/lib/opnix/secrets/sunshinePassword" zeroConfigText}
      ${assertContainsStr "Sunshine secret path" "/var/lib/opnix/secrets/sunshinePassword" streamingModuleText}
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
      ${assertContainsStr "LAN Sunshine hostname" "sunshine.home.buildingbananas.com" zeroConfigText}
      ${assertContainsStr "Cloudflare DNS challenge" "dns cloudflare {env.CLOUDFLARE_API_TOKEN}" caddyNixosModuleText}
      ${assertContainsStr "runtime Cloudflare secret" "/run/secrets/cloudflare-api-token" zeroConfigText}
      ${assertContainsStr "Cloudflare token reference" "Cloudflare DNS API Token/credential" zeroConfigText}
      ${assertContainsStr "OpenCode Go API reference uses the default vault" ''onePasswordItem = "OpenCode Go API/credential"'' zeroConfigText}
      ${assertNotContainsStr "no explicit Homelab secret references" "op://Homelab/" zeroConfigText}
      ${assertContainsStr "Cloudflare Caddy plugin" "caddy-dns/cloudflare@v0.2.4" caddyNixosModuleText}
      ${assertContainsStr "Caddy secret path option" "cloudflareApiTokenPath" caddyNixosModuleText}
      ${assertContainsStr "LAN proxy restriction" "remote_ip 10.0.0.0/8" caddyNixosModuleText}
      ${assertContainsStr "Sunshine upstream TLS override" "upstreamTlsSkipVerify = true" zeroConfigText}
      ${assertContainsStr "Sunshine secret readiness wait" "for attempt in" streamingModuleText}
      ${assertContainsStr "Sunshine secret service ordering" "opnix-secrets.service" streamingModuleText}
      ${assertContainsStr "Sunshine restart delay" "RestartSec = lib.mkForce \"10s\"" streamingModuleText}
      ${assertContainsStr "Sunshine user restart bridge" "systemctl --machine=monkey@.host --user restart sunshine.service" streamingModuleText}
      ${assertContainsStr "HTTPS Sunshine upstream" "https://127.0.0.1:47990" zeroConfigText}
      ${assertContainsStr "Caddy virtual hosts" "virtualHosts = mapAttrs'" caddyNixosModuleText}
      ${assertContainsStr "Caddy firewall" "allowedTCPPorts = [80 443]" caddyNixosModuleText}

      echo "Zero Sunshine Caddy proxy test passed"
      touch $out
    '';

  # Test: Jellyfin should use the existing root filesystem for media and be
  # reachable through Caddy rather than exposing its native port directly.
  zeroJellyfinTest =
    pkgs.runCommand "test-zero-jellyfin"
    {}
    ''
      echo "=== Testing Zero Jellyfin configuration ==="

      ${assertContainsStr "Jellyfin enabled" "jellyfin.enable = true" zeroConfigText}
      ${assertContainsStr "Backups enabled" "backup = {" zeroConfigText}
      ${assertContainsStr "R2 backup repository" "personal-backups/zero" zeroConfigText}
      ${assertContainsStr "Nixarr media root" ''mediaDir = "/srv/media"'' zeroConfigText}
      ${assertContainsStr "Nixarr state root" ''stateDir = "/var/lib/nixarr"'' zeroConfigText}
      ${assertContainsStr "Nixarr backup registration" ''path = "/var/lib/nixarr"'' zeroConfigText}
      ${assertContainsStr "Jellyfin VA-API" ''type = "vaapi"'' zeroConfigText}
      ${assertContainsStr "Jellyfin render device" ''device = "/dev/dri/renderD128"'' zeroConfigText}
      ${assertContainsStr "Jellyfin render group" ''extraGroups = ["render" "video"]'' zeroConfigText}
      ${assertContainsStr "Jellyfin Caddy app" "apps.jellyfin = {" zeroConfigText}
      ${assertContainsStr "Jellyfin hostname" "jellyfin.home.buildingbananas.com" zeroConfigText}
      ${assertContainsStr "Jellyfin upstream" "127.0.0.1:8096" zeroConfigText}
      ${assertContainsStr "backup registry" "myConfig.backup.paths" backupNixosModuleText}
      ${assertContainsStr "Restic integration" "services.restic.backups" backupNixosModuleText}

      echo "Zero Jellyfin configuration test passed"
      touch $out
    '';

  zeroNixRemoteBuilderTest =
    if self == null
    then
      pkgs.runCommand "test-zero-nix-remote-builder-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else let
      zero = self.nixosConfigurations.zero.config;
      builder = lib.findFirst (machine: machine.hostName == "megamanx") null zero.nix.buildMachines;
      builderSecret = zero.myConfig.onepassword.secrets.nixBuilderClientKey or {};
      megamanx = self.darwinConfigurations.MegamanX.config;
      lydia = self.darwinConfigurations.Lydia.config;
      builderUser = megamanx.users.users.nixbuilder or {};
      remoteBuilderUserTrusted = lib.hasInfix "trusted-users = root monkey nixbuilder" megamanx.environment.etc."nix/nix.custom.conf".text;
      builderUserConfigured =
        builderUser
        != {}
        && builderUser.uid == 502
        && builderUser.gid == 20
        && builderUser.createHome == false
        && builderUser.isHidden
        && builtins.toString builderUser.home == "/var/empty"
        && builderUser.shell != null
        && builtins.toString builderUser.shell != "/usr/bin/false"
        && !(builtins.elem "admin" (builderUser.groups or []))
        && builtins.elem "nixbuilder" megamanx.users.knownUsers;
      builderSshConfig = megamanx.services.openssh.extraConfig;
      lydiaSshConfig = lydia.services.openssh.extraConfig or "";
      builderSshAuthenticationRestricted =
        lib.hasInfix "Match User nixbuilder" builderSshConfig
        && lib.hasInfix "AuthenticationMethods publickey" builderSshConfig
        && lib.hasInfix "PasswordAuthentication no" builderSshConfig
        && lib.hasInfix "KbdInteractiveAuthentication no" builderSshConfig
        && lib.hasInfix "AllowAgentForwarding no" builderSshConfig
        && lib.hasInfix "AllowTcpForwarding no" builderSshConfig
        && lib.hasInfix "PermitTTY no" builderSshConfig
        && lib.hasInfix "X11Forwarding no" builderSshConfig
        && lib.hasInfix "ForceCommand /nix/var/nix/profiles/default/bin/nix-daemon --stdio" builderSshConfig
        && lib.hasInfix "Match all" builderSshConfig;
      builderKey =
        if builtins.pathExists ../keys/nix-remote-builder-megamanx.pub
        then builtins.replaceStrings ["\n" "\r"] ["" ""] (builtins.readFile ../keys/nix-remote-builder-megamanx.pub)
        else "";
      configuredCorrectly =
        zero.nix.distributedBuilds
        && zero.nix.settings.builders-use-substitutes
        && builder != null
        && builder.system == "aarch64-darwin"
        && builder.protocol == "ssh-ng"
        && builder.sshUser == "nixbuilder"
        && builder.sshKey == "/run/secrets/nix-builder-client"
        && builder.publicHostKey == "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU9Hd2lqRkxveHN2UVRhcDJScWVrWmdnS3krMlJzVUZDVnRrT28wSWtUN3QK"
        && builderSecret.reference == "Nix Remote Builder Zero to MegamanX/private key"
        && builderSecret.path == "/run/secrets/nix-builder-client"
        && builderSecret.owner == "root"
        && builderSecret.group == "root"
        && builderSecret.mode == "0400"
        && zero.myConfig.onepassword.defaultVault == "Opnix"
        && remoteBuilderUserTrusted
        && builderUserConfigured
        && builderSshAuthenticationRestricted
        && !(lib.hasInfix "nixbuilder" (lydia.environment.etc."nix/nix.custom.conf".text or ""))
        && !(lydia.users.users ? nixbuilder)
        && !(lib.hasInfix "Match User nixbuilder" lydiaSshConfig);
    in
      pkgs.runCommand "test-zero-nix-remote-builder" {} ''
        echo "=== Testing Zero's MegamanX remote builder configuration ==="
        ${
          if configuredCorrectly && builderKey != ""
          then ''echo "Zero's remote builder, Opnix key file, and host pin are configured: OK"''
          else ''echo "FAIL: Zero's remote builder must use the Opnix builder key and pinned MegamanX host"; exit 1''
        }
        touch $out
      '';
}
