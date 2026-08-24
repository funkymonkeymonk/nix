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
  testServices = import ./test-services.nix {inherit pkgs self;};
  testHomeManager = import ./test-home-manager.nix {inherit pkgs;};
  testAgentUser = import ./test-agent-user.nix {inherit pkgs;};
  testWorkspaceSwitch = import ./test-workspace-switch.nix {inherit pkgs;};
  testLlmClient = import ./test-llm-client.nix {inherit pkgs;};
  testGitEnable = import ./test-git-enable.nix {inherit pkgs;};
  testObsidian = import ./test-obsidian.nix {inherit pkgs;};

  testVllmMlx =
    if self != null
    then import ./test-vllm-mlx.nix {inherit pkgs self;}
    else {};
  testVllmMlxStream = import ./test-vllm-mlx-stream.nix {inherit pkgs;};
  testClaudeCode = import ./test-claude-code.nix {inherit pkgs;};
  testPi = import ./test-pi.nix {inherit pkgs;};
  testBifrost = import ./test-bifrost.nix {inherit pkgs;};
  testCaddy = import ./test-caddy.nix {inherit pkgs;};
  testSearxng = import ./test-searxng.nix {inherit pkgs;};
  testLume = import ./test-lume.nix {inherit pkgs;};
  testObservability = import ./test-observability.nix {inherit pkgs;};
  testNixosModules = import ./test-nixos-modules.nix {inherit pkgs;};
  testStackIntegration = import ./test-stack-integration.nix {inherit pkgs;};
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

    # Overlay package build tests (rtk, yaks, pi-coding-agent, bigcodebench)
    overlay-rtk = testOverlayPackages.rtkPackageTest;
    overlay-yaks = testOverlayPackages.yaksPackageTest;
    overlay-pi-coding-agent = testOverlayPackages.piCodingAgentPackageTest;
    overlay-bigcodebench = testOverlayPackages.bigcodebenchPackageTest;

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

    vane-options = testServices.vaneOptionsTest;
    vane-custom-options = testServices.vaneCustomOptionsTest;
    vane-darwin-autostart-default = testServices.vaneDarwinAutoStartDefaultTest;
    vane-darwin-autostart-true = testServices.vaneDarwinAutoStartTrueTest;
    vane-opnix-url-options = testServices.vaneOpnixUrlOptionsTest;
    vane-megamanx-no-ollama-wiring = testServices.vaneMegamanxNoOllamaWiringTest;

    # Home-manager module tests
    opencode-options = testHomeManager.opencodeOptionsTest;
    opencode-custom-options = testHomeManager.opencodeCustomOptionsTest;
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

    # vMLX module tests

    # vllm-mlx module tests
    vllm-mlx-options = testVllmMlx.vllmMlxOptionsTest;
    vllm-mlx-launchd = testVllmMlx.vllmMlxLaunchdTest;
    megamanx-vllm = testVllmMlx.megamanxVllmMlxTest;

    # vllm-mlx package streaming tests (builds the package; darwin-only)
    vllm-mlx-finish-reason = testVllmMlxStream.vllmMlxFinishReasonTest;

    # Claude Code module tests
    claude-code-options = testClaudeCode.claudeCodeOptionsTest;
    claude-code-custom-options = testClaudeCode.claudeCodeCustomOptionsTest;

    # Pi coding agent module tests
    pi-options = testPi.piOptionsTest;
    pi-custom-options = testPi.piCustomOptionsTest;

    # Bifrost AI gateway module tests
    bifrost-options = testBifrost.bifrostOptionsTest;
    bifrost-custom-options = testBifrost.bifrostCustomOptionsTest;
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

    # LLM stack integration test
    stack-integration = testStackIntegration.stackIntegrationTest;

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
