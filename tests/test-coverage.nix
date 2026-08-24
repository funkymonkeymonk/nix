# Module coverage tracking
# Reports what percentage of modules are exercised by the test suite
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Auto-discover all .nix files under modules/ without IFD.
  # Uses recursive builtins.readDir helper — no need to manually update this list.
  #
  # IMPORTANT: build fullPath with `(toString path) + "/${name}"`, NOT
  # `"${path}/${name}"`. String-interpolating a Nix `path` value forces
  # Nix's path-to-string coercion, which copies the path into the Nix
  # store and yields a `/nix/store/HASH-...` string — completely
  # different from `basePrefix` below (computed once via `toString
  # modulesDir`, the plain filesystem path). That mismatch meant
  # `removePrefix basePrefix p` never actually stripped anything, so
  # `allModules` silently contained full store paths instead of clean
  # relative paths, and EVERY module always ended up in
  # `untestedModules` regardless of whether it was actually tested.
  collectNixFiles = path: let
    entries = builtins.readDir path;
  in
    lib.concatLists (
      lib.mapAttrsToList (
        name: type: let
          fullPath = (toString path) + "/${name}";
        in
          if type == "regular" && lib.hasSuffix ".nix" name
          then [fullPath]
          else if type == "directory"
          then collectNixFiles fullPath
          else []
      )
      entries
    );

  modulesDir = ./../modules;
  basePrefix = toString modulesDir + "/";

  allModules = map (p: lib.removePrefix basePrefix p) (collectNixFiles modulesDir);

  # Modules that are exercised by tests (directly imported or evaluated)
  # This includes modules imported by test stubs via evalModules
  testedModules = [
    # Directly tested via test-packages.nix foundationOptionsTest + configValidationTest
    "common/options.nix"
    # Tested via test-packages.nix onepasswordOptionsTest
    "common/onepassword.nix"
    # Tested via test-agent-user.nix (option defaults, disabled/enabled/custom states)
    "common/agent-user.nix"
    # Tested via configValidationTest (imports roles/default.nix)
    "roles/default.nix"
    # All role modules tested via test-roles.nix (evalWithRole imports roles/default.nix
    # which imports all role files)
    "roles/agent-skills.nix"
    "roles/claude.nix"
    "roles/creative.nix"
    "roles/desktop.nix"
    "roles/developer.nix"
    "roles/entertainment.nix"
    "roles/foundation.nix"
    "roles/gaming.nix"
    "roles/opencode.nix"
    "roles/pi.nix"
    "roles/workstation.nix"
    # Tested via test-zero.nix (source-text assertions on opnix secrets
    # wiring, no silent-warning behavior, and env var absence)
    "roles/tailscale.nix"
    # Tested via test-email.nix (email-agent and email-backup module tests)
    "roles/assistant.nix"
    "roles/email-backup.nix"
    "home-manager/email-agent.nix"
    "home-manager/email-backup.nix"
    # Tested via test-llm-client.nix (env var wiring per AI agent role)
    "common/llm-client.nix"
    # Tested via VM integration tests (tests/vm/)
    "nixos/base.nix"
    "common/users.nix"
    "home-manager/themes.nix"
    # Tested via test-packages.nix onepasswordGuardTest + onepasswordConfigOutputTest
    # (hasOpnix guard, platform-specific config output)
    # common/onepassword.nix was already listed above via onepasswordOptionsTest
    # common/lib.nix tested via tests/nix-unit-tests.nix (shared lib helpers)
    "common/lib.nix"
    # Tested via test-services.nix (vane option tests)
    "services/vane/darwin.nix"
    # Tested via test-vllm-mlx.nix (vllm-mlx option defaults, custom
    # values, and MegamanX target config)
    "services/vllm-mlx/darwin.nix"
    "services/vllm-mlx/darwin-instances-options.nix"
    "services/vllm-mlx/darwin-instances-config.nix"
    "services/vllm-mlx/instance-options.nix"
    "services/vllm-mlx/lib.nix"
    # Tested via test-stack-integration.nix (LLM stack composition)
    "services/bifrost/darwin.nix"
    "services/caddy/darwin.nix"
    # Tested via test-searxng.nix (option defaults and custom values)
    "services/searxng/darwin.nix"
    # Tested via test-lume.nix (option defaults and custom values)
    "services/lume/darwin.nix"
    # Tested via test-observability.nix (option defaults, custom values,
    # generated script/scrape-config/alerting-config assertions)
    "services/prometheus/darwin.nix"
    "services/node-exporter/darwin.nix"
    # Tested via test-loki.nix (option defaults, custom values, generated
    # config assertions)
    "services/loki/darwin.nix"
    # Tested via test-vector.nix (option defaults, custom values, generated
    # config assertions)
    "services/vector/darwin.nix"
    # Tested via test-alertmanager.nix (option defaults, custom values,
    # null-receiver placeholder assertions)
    "services/alertmanager/darwin.nix"
    # Tested via test-grafana.nix (option defaults, custom values,
    # datasource/dashboard provisioning assertions)
    "services/grafana/darwin.nix"
    # Tested via test-home-manager.nix (opencode, shell aliases)
    "home-manager/opencode.nix"
    "home-manager/aliases.nix"
    "home-manager/skills/manifest.nix"
    # Tested via test-obsidian.nix (option defaults and custom values)
    "common/obsidian.nix"
    "home-manager/obsidian.nix"
    # Tested via test-log-aggregator.nix (option defaults, enabled wiring,
    # and type-server target wiring)
    "nixos/vector.nix"
    "nixos/loki.nix"
    # Tested via test-nixos-observability.nix (option defaults, enabled
    # wiring, alert rules, alertmanager routing, firewall opt-in, and
    # type-server target wiring)
    "nixos/prometheus.nix"
    "nixos/alertmanager.nix"
  ];

  # Modules not yet covered by tests
  untestedModules = builtins.filter (m: !(builtins.elem m testedModules)) allModules;

  totalCount = builtins.length allModules;
  testedCount = builtins.length testedModules;
  untestedCount = builtins.length untestedModules;

  # Integer percentage (avoid floating point in Nix)
  coveragePct = (testedCount * 100) / totalCount;
  # Regression guard: coverage must not drop below this baseline.
  # Raise this number whenever testedModules grows (i.e. whenever you add
  # a new test that covers a previously-untested module) — this check
  # exists to catch coverage silently regressing (e.g. a module getting
  # added without a matching test, or a testedModules entry going stale
  # after a rename/deletion so it stops actually matching a real file),
  # not to block progress. It should almost always be equal to the
  # current coveragePct, or slightly below it as a small buffer.
  minCoveragePct = 64;
in {
  moduleCoverageTest =
    pkgs.runCommand "test-module-coverage"
    {}
    ''
      echo "=== Module Test Coverage Report ==="
      echo ""
      echo "Total modules:    ${toString totalCount}"
      echo "Tested modules:   ${toString testedCount}"
      echo "Untested modules: ${toString untestedCount}"
      echo "Coverage:         ${toString coveragePct}%"
      echo ""
      echo "--- Tested Modules ---"
      ${lib.concatMapStringsSep "\n" (m: ''echo "  [x] ${m}"'') testedModules}
      echo ""
      echo "--- Untested Modules ---"
      ${lib.concatMapStringsSep "\n" (m: ''echo "  [ ] ${m}"'') untestedModules}
      echo ""

      ${
        if coveragePct >= minCoveragePct
        then ''echo "Coverage ${toString coveragePct}% meets the minimum of ${toString minCoveragePct}%: OK"''
        else ''
          echo "FAIL: Coverage regressed to ${toString coveragePct}%, below the minimum of ${toString minCoveragePct}%."
          echo "Either add tests for the newly-untested module(s) above, or if this is"
          echo "expected (e.g. a module was genuinely removed), lower minCoveragePct in"
          echo "tests/test-coverage.nix to match the new, deliberate baseline."
          exit 1
        ''
      }
      echo ""

      # Write coverage data for CI consumption
      mkdir -p $out
      echo '${builtins.toJSON {
        total = totalCount;
        tested = testedCount;
        untested = untestedCount;
        percentage = coveragePct;
        minPercentage = minCoveragePct;
        untestedList = untestedModules;
      }}' > $out/coverage.json

      echo "Coverage report written to $out/coverage.json"
    '';
}
