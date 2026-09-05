# Nix-based Tests for Foundation
# These tests use nix eval and can run in CI
{
  pkgs,
  self ? null,
  ...
}: let
  # Test utilities
  testPackages = import ./test-packages.nix {inherit pkgs;};
  testOverlayPackages = import ./test-overlay-packages.nix {inherit pkgs;};
  testCrossPlatformGuards = import ./test-cross-platform-guards.nix {inherit pkgs;};
  testRoles = import ./test-roles.nix {inherit pkgs;};
  testCoverage = import ./test-coverage.nix {inherit pkgs;};
  testSkills = import ./test-skills.nix {inherit pkgs;};
  testCanonicalSkillsInstall = import ./test-skills-canonical-install.nix {inherit pkgs;};
  testEmail = import ./test-email.nix {inherit pkgs;};
  testSketchybarRemoved = import ./test-sketchybar-removed.nix {inherit pkgs;};
  testHomeManager = import ./test-home-manager.nix {inherit pkgs;};
  testAgentUser = import ./test-agent-user.nix {inherit pkgs;};
  testWorkspaceSwitch = import ./test-workspace-switch.nix {inherit pkgs;};
  testLlmClient = import ./test-llm-client.nix {inherit pkgs;};
  testGitEnable = import ./test-git-enable.nix {inherit pkgs;};
  testObsidian = import ./test-obsidian.nix {inherit pkgs;};

  testClaudeCode = import ./test-claude-code.nix {inherit pkgs;};
  testPi = import ./test-pi.nix {inherit pkgs;};
  testBifrost = import ./test-bifrost.nix {inherit pkgs;};
  testCaddy = import ./test-caddy.nix {inherit pkgs;};
  testSearxng = import ./test-searxng.nix {inherit pkgs;};
  testLume = import ./test-lume.nix {inherit pkgs;};
  testObservability = import ./test-observability.nix {inherit pkgs;};
  testTemporal = import ./test-temporal.nix {inherit pkgs;};
  testNixosModules = import ./test-nixos-modules.nix {inherit pkgs;};
  testLoki = import ./test-loki.nix {inherit pkgs;};
  testVector = import ./test-vector.nix {inherit pkgs;};
  testAlertmanager = import ./test-alertmanager.nix {inherit pkgs;};
  testGrafana = import ./test-grafana.nix {inherit pkgs;};
  testLogAggregator = import ./test-log-aggregator.nix {inherit pkgs self;};
  testNixosObservability = import ./test-nixos-observability.nix {inherit pkgs self;};
  testZero = import ./test-zero.nix {inherit pkgs;};
  testCoreBootstrap = import ./test-phase5-core-bootstrap.nix {inherit pkgs self;};
  testPhase3Zero = import ./test-phase3-zero.nix {inherit pkgs self;};
  testPhase4DarwinServer = import ./test-phase4-darwin-server.nix {inherit pkgs self;};
  testPhase2Cattle = import ./test-phase2-cattle.nix {inherit pkgs self;};
  testLibrary =
    if self != null
    then import ./test-library.nix {inherit pkgs self;}
    else {};
  testMkUser = import ./test-mk-user.nix {inherit pkgs;};
  testFlakeModule = import ./test-flake-module.nix {inherit pkgs;};
  testOptionsDoc =
    if self != null
    then import ./test-options-doc.nix {inherit pkgs self;}
    else {};
  # VM tests only available on x86_64-linux (NixOS testing framework)
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  vmTests =
    if isLinux && self != null
    then import ./vm {inherit pkgs self;}
    else {};
  # mkRoleVmTest generator tests: build their own x86_64-linux pkgs
  # (mirroring flake.nix) so they can run on any host platform, including
  # aarch64-darwin dev machines where tests/vm/default.nix itself is never
  # imported by the block above.
  testVmRoleGenerator =
    if self != null
    then import ./test-vm-role-generator.nix {inherit pkgs self;}
    else {};

  # nix-unit eval-time tests (fast, no derivation builds)
  # Copies the full repo into the build dir so relative imports resolve.
  nix-unit-tests = let
    src = builtins.path {
      path = ../.;
      name = "source";
    };
  in
    pkgs.runCommand "nix-unit-tests"
    {
      nativeBuildInputs = [pkgs.nix-unit pkgs.nix];
      NIX_PATH = "nixpkgs=${toString pkgs.path}";
    }
    ''
      cp -r ${src} source
      export HOME=$(mktemp -d)
      nix-unit source/tests/nix-unit-tests.nix --eval-store "$HOME"
      touch $out
    '';
in
  {
    # nix-unit eval-time tests (fast, no derivation builds)
    inherit nix-unit-tests;

    # Package availability tests
    core-packages = testPackages.corePackagesTest;
    foundation-packages = testPackages.foundationPackagesTest;

    # Overlay package build tests (rtk, yaks, pi-coding-agent, bigcodebench, evalscope)
    overlay-qwen38-mxfp4 = testOverlayPackages.qwen38Mxfp4PackageTest;
    overlay-rtk = testOverlayPackages.rtkPackageTest;
    overlay-yaks = testOverlayPackages.yaksPackageTest;
    overlay-pi-coding-agent = testOverlayPackages.piCodingAgentPackageTest;
    overlay-bigcodebench = testOverlayPackages.bigcodebenchPackageTest;
    overlay-evalscope = testOverlayPackages.evalscopePackageTest;
    overlay-openai-evals = testOverlayPackages.openaiEvalsPackageTest;

    # Benchmark package build tests (HumanEval + MBPP)
    overlay-humaneval-mbpp = testOverlayPackages.humanevalMbppPackageTest;

    # Cross-platform option guard tests (Darwin vs Linux branches in role modules)
    cross-platform-desktop-guard = testCrossPlatformGuards.crossPlatformDesktopGuardTest;
    cross-platform-entertainment-guard = testCrossPlatformGuards.crossPlatformEntertainmentGuardTest;
    cross-platform-creative-control = testCrossPlatformGuards.crossPlatformCreativeControlTest;

    # Configuration validation tests
    config-validation = testPackages.configValidationTest;

    # Option validation tests
    foundation-options = testPackages.foundationOptionsTest;

    # Per-role tests (all combined into one derivation for CI speed)
    all-role-tests = testRoles.allRoleTests;

    # Skills tests
    skills-manifest = testSkills.manifestValidationTest;
    skills-autoload-filtering = testSkills.autoLoadFilteringTest;
    skills-autoload-content = testSkills.autoLoadContentTest;
    skills-role-filtering = testSkills.roleFilteringTest;
    skills-external-identification = testSkills.externalSkillsIdentificationTest;
    skills-external-command-generation = testSkills.externalSkillCommandGenerationTest;
    skills-external-empty-case = testSkills.externalSkillsEmptyTest;

    # Canonical skill install location tests (~/.agents/skills/<name>)
    skills-canonical-install-writes-agents-skills = testCanonicalSkillsInstall.canonicalInstallWritesAgentsSkillsTest;
    skills-canonical-install-gated-on-empty-roles = testCanonicalSkillsInstall.canonicalInstallGatedOnEmptyRolesTest;
    skills-opencode-no-longer-writes-own-dirs = testCanonicalSkillsInstall.opencodeNoLongerWritesOwnSkillDirsTest;
    skills-opencode-commands-still-work = testCanonicalSkillsInstall.opencodeSkillCommandsStillWorkTest;
    skills-pi-no-longer-writes-manifest-dirs = testCanonicalSkillsInstall.piNoLongerWritesManifestSkillDirsTest;
    skills-agent-skills-path-canonical = testCanonicalSkillsInstall.agentSkillsPathPointsAtCanonicalLocationTest;

    # Coverage tracking
    module-coverage = testCoverage.moduleCoverageTest;

    # Email module tests
    email-agent-options = testEmail.emailAgentOptionsTest;
    email-backup-options = testEmail.emailBackupOptionsTest;
    email-custom-options = testEmail.emailCustomOptionsTest;
    email-composition = testEmail.emailCompositionTest;
    email-backup-scripts = testEmail.emailBackupScriptsTest;
    email-separation = testEmail.emailSeparationTest;

    # 1Password guard and config output tests
    onepassword-guard = testPackages.onepasswordGuardTest;
    onepassword-config-output = testPackages.onepasswordConfigOutputTest;

    # Structural / deduplication tests
    zsh-enable-single-location = testPackages.zshEnableSingleLocationTest;

    # bfcl benchmark package metadata (see comment on the test itself for
    # why this doesn't force a full build)
    bfcl-package-metadata = testPackages.bfclPackageMetadataTest;

    # Sketchybar removal regression tests (module was removed — see AGENTS.md history)
    sketchybar-module-removed = testSketchybarRemoved.sketchybarModuleRemovedTest;
    sketchybar-options-removed = testSketchybarRemoved.sketchybarOptionsRemovedTest;
    sketchybar-wiring-removed = testSketchybarRemoved.sketchybarWiringRemovedTest;

    # Service module tests
    temporal-options = testTemporal.temporalOptionsTest;

    # Home-manager module tests
    opencode-options = testHomeManager.opencodeOptionsTest;
    opencode-custom-options = testHomeManager.opencodeCustomOptionsTest;
    opencode-bifrost-defaults = testHomeManager.opencodeBifrostDefaultsTest;
    opencode-provider-opnix-url = testHomeManager.opencodeProviderOpnixUrlTest;
    shell-aliases = testHomeManager.shellAliasesTest;

    # Workspace-aware switch shell function tests
    workspace-switch = testWorkspaceSwitch.workspaceSwitchTest;

    # Aerospace option tests
    aerospace-options = testHomeManager.aerospaceOptionsTest;
    aerospace-custom-options = testHomeManager.aerospaceCustomOptionsTest;

    # LLM client module tests
    llm-client-opencode = testLlmClient.llmClientOpencodeTest;
    llm-client-claude = testLlmClient.llmClientClaudeTest;
    llm-client-pi = testLlmClient.llmClientPiTest;
    llm-client-custom-host = testLlmClient.llmClientCustomHostTest;
    llm-client-no-ai-roles = testLlmClient.llmClientNoAiRolesTest;

    # Git configuration tests
    git-enable = testGitEnable.gitEnableSimpleTest;
    git-settings-exist = testGitEnable.gitSettingsExistTest;
    git-commit-signing = testGitEnable.gitCommitSigningExistsTest;
    git-config-generation = testGitEnable.gitConfigGenerationTest;
    git-user-config = testGitEnable.gitUserConfigTest;

    # Obsidian option tests
    obsidian-options = testObsidian.obsidianOptionsTest;
    obsidian-custom-options = testObsidian.obsidianCustomOptionsTest;

    # NixOS module option tests
    typed-attrs-options = testNixosModules.typedAttrsOptionsTest;

    # Zero target tests
    zero-tailscale-opnix-dep = testZero.zeroTailscaleOpnixDepTest;
    zero-tailscale-no-env-var = testZero.zeroTailscaleNoEnvVarTest;
    zero-tailscale-secret-file = testZero.zeroTailscaleSecretFileTest;
    zero-tailscale-fail-loud = testZero.zeroTailscaleFailLoudTest;
    zero-tailscale-secret-config = testZero.zeroTailscaleSecretConfigTest;

    # Core and bootstrap configs
    core-bootstrap = testCoreBootstrap.coreBootstrapTest;

    # Phase 3: Real-machine migration — zero v2
    phase3-zero = testPhase3Zero.phase3ZeroTest;
    phase3-zero-flake-parts = testPhase3Zero.phase3ZeroFlakePartsTest;

    # Phase 4: darwin-server v2 migration
    phase4-darwin-server = testPhase4DarwinServer.phase4DarwinServerTest;

    # library/lib/mk-system.nix builder tests
    mk-darwin-system =
      if testLibrary != {}
      then testLibrary.mkDarwinSystemTest
      else null;
    mk-nixos-system =
      if testLibrary != {}
      then testLibrary.mkNixosSystemTest
      else null;

    # library/lib/mk-user.nix builder tests
    mk-user = testMkUser.mkUserTest;
    mk-user-calling-convention = testMkUser.mkUserCallingConventionTest;

    # library/flake-module.nix shared module args tests
    flake-module-args = testFlakeModule.flakeModuleArgsTest;
    flake-module-library-export = testFlakeModule.flakeModuleLibraryExportTest;

    # agent-user module tests
    agent-user-options = testAgentUser.agentUserOptionsTest;
    agent-user-disabled = testAgentUser.agentUserDisabledTest;
    agent-user-enabled = testAgentUser.agentUserEnabledTest;
    agent-user-custom = testAgentUser.agentUserCustomTest;

    # Claude Code module tests
    claude-code-options = testClaudeCode.claudeCodeOptionsTest;
    claude-code-custom-options = testClaudeCode.claudeCodeCustomOptionsTest;

    # Pi coding agent module tests
    pi-options = testPi.piOptionsTest;
    pi-custom-options = testPi.piCustomOptionsTest;

    # Bifrost AI gateway module tests
    bifrost-options = testBifrost.bifrostOptionsTest;
    bifrost-custom-options = testBifrost.bifrostCustomOptionsTest;
    bifrost-anthropic-config = testBifrost.bifrostAnthropicConfigTest;
    bifrost-retry-config = testBifrost.bifrostRetryConfigTest;

    # Caddy reverse proxy module tests
    caddy-options = testCaddy.caddyOptionsTest;
    caddy-custom-options = testCaddy.caddyCustomOptionsTest;

    # SearXNG module tests
    searxng-options = testSearxng.searxngOptionsTest;
    searxng-custom-options = testSearxng.searxngCustomOptionsTest;

    # Lume module tests
    lume-options = testLume.lumeOptionsTest;
    lume-custom-options = testLume.lumeCustomOptionsTest;

    # Observability module tests
    node-exporter-options = testObservability.nodeExporterOptionsTest;
    node-exporter-custom-options = testObservability.nodeExporterCustomOptionsTest;
    prometheus-options = testObservability.prometheusOptionsTest;
    prometheus-custom-options = testObservability.prometheusCustomOptionsTest;
    prometheus-generated-script = testObservability.prometheusGeneratedScriptTest;
    prometheus-scrape-config = testObservability.prometheusScrapeConfigTest;
    prometheus-alerting-config = testObservability.prometheusAlertingConfigTest;

    # Loki log aggregation module tests
    loki-options = testLoki.lokiOptionsTest;
    loki-custom-options = testLoki.lokiCustomOptionsTest;
    loki-generated-config = testLoki.lokiGeneratedConfigTest;

    # Vector log shipper module tests
    vector-options = testVector.vectorOptionsTest;
    vector-custom-options = testVector.vectorCustomOptionsTest;
    vector-generated-config = testVector.vectorGeneratedConfigTest;

    # Alertmanager module tests
    alertmanager-options = testAlertmanager.alertmanagerOptionsTest;
    alertmanager-custom-options = testAlertmanager.alertmanagerCustomOptionsTest;
    alertmanager-null-receiver = testAlertmanager.alertmanagerNullReceiverTest;

    # Grafana module tests
    grafana-options = testGrafana.grafanaOptionsTest;
    grafana-custom-options = testGrafana.grafanaCustomOptionsTest;
    grafana-datasources = testGrafana.grafanaDatasourcesTest;
    grafana-federated-datasource = testGrafana.grafanaFederatedDatasourceTest;

    # Log aggregator (Vector + Loki) module tests for NixOS
    # (renamed with a nixos- prefix to avoid colliding with the Darwin
    # vector/loki module test names above, which were added independently
    # in a separately-merged PR)
    nixos-vector-options = testLogAggregator.vectorOptionsTest;
    nixos-vector-enabled = testLogAggregator.vectorEnabledTest;
    nixos-vector-custom-endpoint = testLogAggregator.vectorCustomEndpointTest;
    nixos-loki-options = testLogAggregator.lokiOptionsTest;
    nixos-loki-enabled = testLogAggregator.lokiEnabledTest;
    nixos-loki-firewall = testLogAggregator.lokiFirewallTest;
    type-server-log-aggregator = testLogAggregator.typeServerLogAggregatorTest;

    # NixOS observability (Prometheus + Alertmanager) module tests
    nixos-prometheus-options = testNixosObservability.prometheusOptionsTest;
    nixos-node-exporter-options = testNixosObservability.nodeExporterOptionsTest;
    nixos-prometheus-enabled = testNixosObservability.prometheusEnabledTest;
    nixos-prometheus-alert-rules = testNixosObservability.prometheusAlertRulesTest;
    nixos-prometheus-alertmanager-wiring = testNixosObservability.prometheusAlertmanagerWiringTest;
    nixos-prometheus-firewall = testNixosObservability.prometheusFirewallTest;
    nixos-alertmanager-options = testNixosObservability.alertmanagerOptionsTest;
    nixos-alertmanager-null-receiver = testNixosObservability.alertmanagerNullReceiverTest;
    type-server-observability = testNixosObservability.typeServerObservabilityTest;

    # LLM stack integration test

    # Phase 2: Cattle NixOS v2 configs
    phase2-cattle = testPhase2Cattle.phase2CattleTest;

    # mkRoleVmTest generator: structural + binary-resolution tests
    vm-role-generator =
      if testVmRoleGenerator != {}
      then testVmRoleGenerator.vmRoleGeneratorTest
      else null;

    # Auto-generated docs/reference/options.md tests (see
    # scripts/generate-options-doc.nix)
    options-doc-known-option =
      if testOptionsDoc != {}
      then testOptionsDoc.optionsDocKnownOptionTest
      else null;
    options-doc-submodule-recursion =
      if testOptionsDoc != {}
      then testOptionsDoc.optionsDocSubmoduleRecursionTest
      else null;
    options-doc-fresh =
      if testOptionsDoc != {}
      then testOptionsDoc.optionsDocFreshTest
      else null;
  }
  // vmTests
