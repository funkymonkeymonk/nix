# Catalog and resolved-configuration checks for the shared Tailscale enrollment policy.
{
  pkgs,
  self,
  inputs,
  ...
}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  manifest = builtins.fromTOML (builtins.readFile ../secretspec.toml);

  machine = name: entry: systemConfig: expectedTags: {
    inherit name expectedTags;
    catalogPolicy = entry.overrides.tailscale or {};
    configuredPolicy = systemConfig.myConfig.tailscale;
    staticKeyConfigured = systemConfig.myConfig.onepassword.secrets ? tailscaleAuthKey;
  };

  enabledMachines = [
    (machine "type-nas" catalog.type-nas self.nixosConfigurations.type-nas.config ["tag:home-lab"])
    (machine "type-server" catalog.type-server self.nixosConfigurations.type-server.config ["tag:home-lab"])
    (machine "zero" catalog.zero self.nixosConfigurations.zero.config ["tag:home-lab"])
    (machine "drlight" catalog.drlight self.nixosConfigurations.drlight.config ["tag:home-lab" "tag:media-center"])
    (machine "MegamanX" catalog.MegamanX self.darwinConfigurations.MegamanX.config ["tag:home-lab"])
  ];

  machinePolicyValid = item:
    (item.catalogPolicy.enable or false)
    == true
    && item.configuredPolicy.enable == true
    && (item.catalogPolicy.authKeyTags or []) == item.expectedTags
    && item.configuredPolicy.authKeyTags == item.expectedTags
    && !(item.catalogPolicy ? authKeyMode)
    && !(item.catalogPolicy ? authKeyOpnixItem)
    && !(item.configuredPolicy ? authKeyMode)
    && !(item.configuredPolicy ? authKeyOpnixItem)
    && !item.staticKeyConfigured;

  armServer = catalog.type-server-arm;
  armServerConfig = self.nixosConfigurations.type-server-arm.config;
  armServerDisabled =
    (armServer.overrides.tailscale.enable or null)
    == false
    && armServerConfig.myConfig.tailscale.enable == false;

  megamanxProfile = manifest.profiles.MegamanX or {};
  validSecretRef = name: field: let
    secret = megamanxProfile.${name} or null;
  in
    secret
    != null
    && secret.ref.item == "Tailscale Oauth"
    && secret.ref.field == field
    && secret.providers == ["opnix"];

  credentialsScoped =
    validSecretRef "TAILSCALE_OAUTH_CLIENT_ID" "Client ID"
    && validSecretRef "TAILSCALE_OAUTH_CLIENT_SECRET" "Client secret";

  zeroConfig = self.nixosConfigurations.zero.config;
  zeroAuthDaemon = zeroConfig.systemd.services."tailscale-autoconnect" or {};
  zeroAuthScript = zeroAuthDaemon.script or "";
  mockSleep = pkgs.writeShellScriptBin "sleep" ''exit 0'';
  unknownStatusScript =
    builtins.replaceStrings
    [(lib.escapeShellArg "/run/devenv/tailscale-auth-key")]
    ["\"$TMPDIR/auth-key\""]
    zeroAuthScript;
  zeroAuthAdapterValid =
    zeroConfig.services.tailscale.enable
    && (zeroAuthDaemon.serviceConfig.Type or null) == "oneshot"
    && lib.hasInfix "/run/devenv/tailscale-auth-key" zeroAuthScript
    && lib.hasInfix "tailscale status --json" zeroAuthScript
    && lib.hasInfix "BackendState" zeroAuthScript
    && lib.hasInfix "Running" zeroAuthScript
    && lib.hasInfix "tailscale up" zeroAuthScript
    && lib.hasInfix "rm -f" zeroAuthScript;

  megamanxConfig = self.darwinConfigurations.MegamanX.config;
  megamanxAuthDaemon = megamanxConfig.launchd.daemons."tailscale-autoconnect" or {};
  megamanxAuthScript = megamanxAuthDaemon.command or "";
  megamanxAuthServiceConfig = megamanxAuthDaemon.serviceConfig or {};
  megamanxAuthAdapterValid =
    megamanxConfig.services.tailscale.enable
    && (megamanxConfig.launchd.daemons.tailscaled.serviceConfig.KeepAlive or false)
    && (megamanxAuthServiceConfig.RunAtLoad or false)
    && builtins.elem "/tmp/devenv-tailscale-auth-key" (megamanxAuthServiceConfig.WatchPaths or [])
    && megamanxAuthScript != "";

  megamanxServeMapping = (megamanxConfig.myConfig.tailscale.serve or {}).bifrost or {};
  megamanxServeDaemon = megamanxConfig.launchd.daemons."tailscale-serve-bifrost" or {};
  megamanxServeScript = megamanxServeDaemon.command or "";
  megamanxServeValid =
    (megamanxServeMapping.port or null)
    == 8081
    && (megamanxServeMapping.target or null) == "http://127.0.0.1:8081"
    && (megamanxServeMapping.readinessUrl or null) == "http://127.0.0.1:8081/v1/models"
    && (megamanxServeDaemon.serviceConfig.RunAtLoad or false)
    && megamanxServeScript != "";

  darwinScriptChecks =
    if pkgs.stdenv.hostPlatform.isDarwin
    then ''
      AUTH_SCRIPT=${lib.escapeShellArg megamanxAuthScript}
      AUTH_HELPER=${lib.escapeShellArg ../scripts/tailscale-darwin-autoconnect.sh}
      SERVE_SCRIPT=${lib.escapeShellArg megamanxServeScript}
      ${pkgs.bash}/bin/bash -n "$AUTH_SCRIPT"
      ${pkgs.bash}/bin/bash -n "$AUTH_HELPER"
      ${pkgs.bash}/bin/bash -n "$SERVE_SCRIPT"
      if grep -qF 'tailscale-darwin-autoconnect.sh' "$AUTH_SCRIPT" \\
        && grep -qF '/tmp/devenv-tailscale-auth-key' "$AUTH_SCRIPT" \\
        && grep -q 'NeedsLogin' "$AUTH_HELPER" \\
        && grep -q 'Starting|NoState' "$AUTH_HELPER" \\
        && grep -q 'unsupported' "$AUTH_HELPER" \\
        && grep -q 'tailscale_bin.*up' "$AUTH_HELPER" \\
        && grep -q 'rm -f' "$AUTH_HELPER"; then
        echo "  Darwin auth adapter delegates to the tested fail-closed state helper: OK"
      else
        echo "FAIL: Darwin auth adapter must use the bounded fail-closed helper"; exit 1
      fi
      if grep -q 'tailscale ip -4' "$SERVE_SCRIPT" \\
        && grep -q 'http://127.0.0.1:8081/v1/models' "$SERVE_SCRIPT" \\
        && grep -q 'tailscale serve --bg --http=8081' "$SERVE_SCRIPT" \\
        && grep -q 'http://127.0.0.1:8081' "$SERVE_SCRIPT" \\
        && ! grep -q 'tailscale funnel' "$SERVE_SCRIPT"; then
        echo "  Tailscale Serve waits for readiness and remains tailnet-only: OK"
      else
        echo "FAIL: Serve script must wait for readiness and must not configure Funnel"; exit 1
      fi
      echo "  generated Darwin service scripts parse: OK"
    ''
    else ''
      echo "  Darwin launchd script contents are validated on Darwin runners"
    '';

  machineSummary = item: "${item.name}: catalog.enable=${toString (item.catalogPolicy.enable or false)}, config.enable=${toString item.configuredPolicy.enable}, catalog.tags=${builtins.toJSON (item.catalogPolicy.authKeyTags or [])}, config.tags=${builtins.toJSON (item.configuredPolicy.authKeyTags or [])}, staticSecret=${toString item.staticKeyConfigured}";
  minimalNixosBase =
    (lib.evalModules {
      modules =
        stubs.base
        ++ stubs.nixosService
        ++ [
          {
            options.system.autoUpgrade = lib.mkOption {
              type = lib.types.anything;
              default = {};
            };
            options.virtualisation = lib.mkOption {
              type = lib.types.anything;
              default = {};
            };
            options.assertions = lib.mkOption {
              type = lib.types.listOf lib.types.anything;
              default = [];
            };
            options.systemd.timers = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = {};
            };
            config.myConfig.users = [];
          }
          ../modules/nixos/base.nix
        ];
    }).config;
  minimalNixosTailscaleService = (minimalNixosBase.systemd.services or {}).tailscale-autoconnect or {};
  minimalNixosDoesNotEnableTailscale =
    !(minimalNixosTailscaleService ? script)
    && !(minimalNixosBase.services.tailscale.enable or false);
  report = lib.concatMapStringsSep "\n" machineSummary enabledMachines;
  enrollmentGuide = builtins.readFile ../docs/how-to/enroll-megamanx-in-tailscale.md;
  enrollmentGuideUsesOAuthFlow =
    lib.hasInfix "devenv tasks run machines:plan" enrollmentGuide
    && lib.hasInfix "devenv tasks run machines:apply" enrollmentGuide
    && lib.hasInfix "deployment-generated Tailscale OAuth key flow" enrollmentGuide
    && lib.hasInfix "NeedsLogin" enrollmentGuide
    && lib.hasInfix "tag:home-lab" enrollmentGuide
    && !(lib.hasInfix "sudo tailscale up" enrollmentGuide)
    && !(lib.hasInfix "sudo /run/current-system/sw/bin/tailscale up" enrollmentGuide);
in {
  tailscaleDarwinAutoconnect =
    pkgs.runCommand "test-tailscale-darwin-autoconnect" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils];
    } ''
      TAILSCALE_DARWIN_AUTH_SCRIPT=${lib.escapeShellArg ../scripts/tailscale-darwin-autoconnect.sh} \
        ${pkgs.bash}/bin/bash ${../tests/test-tailscale-darwin-autoconnect.sh}
      touch $out
    '';

  tailscaleEnrollmentPolicy = pkgs.runCommand "test-tailscale-enrollment-policy" {} ''
    echo "=== Checking catalogued Tailscale enrollment policy ==="
    if ${lib.boolToString minimalNixosDoesNotEnableTailscale}; then
      echo "  minimal NixOS base safely leaves the optional Tailscale role disabled: OK"
    else
      echo "FAIL: the NixOS base must tolerate absent Tailscale policy"
      exit 1
    fi
    ${lib.concatMapStringsSep "\n" (item: ''
        if ${lib.boolToString (machinePolicyValid item)}; then
          echo "  ${item.name} uses catalogued OAuth enrollment policy: OK"
        else
          echo "FAIL: ${item.name} does not match the catalogued OAuth enrollment policy"
          echo "${lib.escapeShellArg (machineSummary item)}"
          exit 1
        fi
      '')
      enabledMachines}
    if ${lib.boolToString armServerDisabled}; then
      echo "  type-server-arm remains Tailscale-disabled: OK"
    else
      echo "FAIL: type-server-arm must remain Tailscale-disabled"
      exit 1
    fi
    if ${lib.boolToString credentialsScoped}; then
      echo "  MegamanX OAuth references use the approved Opnix provider: OK"
    else
      echo "FAIL: MegamanX must reference both existing Tailscale OAuth fields through Opnix"
      exit 1
    fi
    if ${lib.boolToString zeroAuthAdapterValid}; then
      echo "  NixOS keeps the idempotent deployment-key adapter: OK"
    else
      echo "FAIL: NixOS must use the deployment key only when disconnected"
      exit 1
    fi
    if ${lib.boolToString megamanxAuthAdapterValid}; then
      echo "  Darwin watches and consumes the staged OAuth key: OK"
    else
      echo "FAIL: Darwin needs a privileged launchd OAuth adapter"
      exit 1
    fi
    if ${lib.boolToString megamanxServeValid}; then
      echo "  Bifrost Serve is declared by central Tailscale policy: OK"
    else
      echo "FAIL: Tailscale policy must own Bifrost's tailnet-only Serve mapping"
      exit 1
    fi
    NIXOS_AUTH_SCRIPT=${lib.escapeShellArg zeroAuthScript}
    printf '%s\\n' "$NIXOS_AUTH_SCRIPT" > ./tailscale-autoconnect.sh
    ${pkgs.bash}/bin/bash -n ./tailscale-autoconnect.sh
    echo "  generated NixOS auth script parses: OK"

    printf '%s\\n' ${lib.escapeShellArg unknownStatusScript} > "$TMPDIR/unknown-status.sh"
    ${pkgs.gnused}/bin/sed -e 's|^status=.*|status=unknown|' -e 's|^sleep 2$|:|' -e 's|^[[:space:]]*.*tailscale up .*|echo up >> "$TAILSCALE_CALLS"|' "$TMPDIR/unknown-status.sh" > "$TMPDIR/mock-auth.sh"
    if ! grep -q '^status=unknown$' "$TMPDIR/mock-auth.sh" || ! grep -q '^echo up' "$TMPDIR/mock-auth.sh"; then
      echo "FAIL: could not prepare deterministic unknown-status script"; exit 1
    fi
    touch "$TMPDIR/auth-key"
    set +e
    TAILSCALE_CALLS="$TMPDIR/tailscale-calls" \
      PATH=${lib.makeBinPath [mockSleep]}:"$PATH" \
      ${pkgs.bash}/bin/bash "$TMPDIR/mock-auth.sh" >"$TMPDIR/stdout" 2>"$TMPDIR/stderr"
    auth_status=$?
    set -e
    unknown_status_failures=0
    if [ "$auth_status" -eq 0 ]; then
      echo "FAIL: unknown Tailscale status must fail closed"
      unknown_status_failures=1
    fi
    if [ ! -f "$TMPDIR/auth-key" ]; then
      echo "FAIL: unknown Tailscale status consumed the staged auth key"
      unknown_status_failures=1
    fi
    if [ -f "$TMPDIR/tailscale-calls" ] && grep -q '^up' "$TMPDIR/tailscale-calls"; then
      echo "FAIL: unknown Tailscale status attempted tailscale up"
      unknown_status_failures=1
    fi
    if [ "$unknown_status_failures" -ne 0 ]; then
      exit 1
    fi
    echo "  unknown Tailscale status preserves the key and skips auth: OK"
    if ${lib.boolToString enrollmentGuideUsesOAuthFlow}; then
      echo "  MegamanX guide documents named OAuth enrollment without manual key auth: OK"
    else
      echo "FAIL: MegamanX guide must document named plan/apply OAuth enrollment and omit manual auth"
      exit 1
    fi
    ${darwinScriptChecks}
    echo "${lib.escapeShellArg report}"
    touch $out
  '';
}
