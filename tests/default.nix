# Nix-based Tests for Foundation
# These tests use nix eval and can run in CI
{
  pkgs,
  self ? null,
  ...
}: let
  # Test utilities
  testPackages = import ./test-packages.nix {inherit pkgs;};
  testRoles = import ./test-roles.nix {inherit pkgs;};
  testCoverage = import ./test-coverage.nix {inherit pkgs;};
  testSkills = import ./test-skills.nix {inherit pkgs;};
  testEmail = import ./test-email.nix {inherit pkgs;};
  testSketchybar = import ./test-sketchybar.nix {inherit pkgs;};
  testServices = import ./test-services.nix {inherit pkgs;};
  testHomeManager = import ./test-home-manager.nix {inherit pkgs;};
  testWorkspaceSwitch = import ./test-workspace-switch.nix {inherit pkgs;};
  testMicrovm = import ./test-microvm.nix {inherit pkgs;};
  testLlmClient = import ./test-llm-client.nix {inherit pkgs;};

  testVllmMlx = import ./test-vllm-mlx.nix {inherit pkgs;};
  testClaudeCode = import ./test-claude-code.nix {inherit pkgs;};
  testPi = import ./test-pi.nix {inherit pkgs;};
  testBifrost = import ./test-bifrost.nix {inherit pkgs;};
  testCaddy = import ./test-caddy.nix {inherit pkgs;};
  testSearxng = import ./test-searxng.nix {inherit pkgs;};
  testLume = import ./test-lume.nix {inherit pkgs;};
  testNixosModules = import ./test-nixos-modules.nix {inherit pkgs;};
  testStackIntegration = import ./test-stack-integration.nix {inherit pkgs;};
  testZero = import ./test-zero.nix {inherit pkgs;};
  testCoreBootstrap = import ./test-phase5-core-bootstrap.nix {inherit pkgs self;};
  testPhase3Zero = import ./test-phase3-zero.nix {inherit pkgs self;};
  testPhase4DarwinServer = import ./test-phase4-darwin-server.nix {inherit pkgs self;};
  testPhase2Cattle = import ./test-phase2-cattle.nix {inherit pkgs self;};

  # VM tests only available on x86_64-linux (NixOS testing framework)
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  vmTests =
    if isLinux && self != null
    then import ./vm {inherit pkgs self;}
    else {};
in
  {
    # Package availability tests
    core-packages = testPackages.corePackagesTest;
    foundation-packages = testPackages.foundationPackagesTest;

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

    # Sketchybar tests
    sketchybar-options = testSketchybar.sketchybarOptionsTest;
    sketchybar-custom-options = testSketchybar.sketchybarCustomOptionsTest;
    sketchybar-theme = testSketchybar.sketchybarThemeTest;
    sketchybar-color-conversion = testSketchybar.sketchybarColorConversionTest;
    sketchybar-platform-guard = testSketchybar.sketchybarPlatformGuardTest;
    sketchybar-entrypoint = testSketchybar.sketchybarEntryPointTest;

    # Service module tests

    vane-options = testServices.vaneOptionsTest;
    vane-custom-options = testServices.vaneCustomOptionsTest;
    openclaw-options = testServices.openclawOptionsTest;
    vane-darwin-autostart-default = testServices.vaneDarwinAutoStartDefaultTest;
    vane-darwin-autostart-true = testServices.vaneDarwinAutoStartTrueTest;
    vane-opnix-url-options = testServices.vaneOpnixUrlOptionsTest;

    # Home-manager module tests
    opencode-options = testHomeManager.opencodeOptionsTest;
    opencode-custom-options = testHomeManager.opencodeCustomOptionsTest;
    opencode-provider-opnix-url = testHomeManager.opencodeProviderOpnixUrlTest;
    shell-aliases = testHomeManager.shellAliasesTest;

    # Workspace-aware switch shell function tests
    workspace-switch = testWorkspaceSwitch.workspaceSwitchTest;
    fjj-options = testHomeManager.fjjOptionsTest;
    fjj-custom-options = testHomeManager.fjjCustomOptionsTest;

    # Aerospace option tests
    aerospace-options = testHomeManager.aerospaceOptionsTest;
    aerospace-custom-options = testHomeManager.aerospaceCustomOptionsTest;

    # MicroVM tests
    microvm-config = testMicrovm.mediaCenterConfigTest;
    microvm-jellyfin = testMicrovm.mediaCenterJellyfinTest;
    microvm-arr-services = testMicrovm.mediaCenterArrServicesTest;
    microvm-transmission = testMicrovm.mediaCenterTransmissionTest;
    microvm-nginx = testMicrovm.mediaCenterNginxTest;
    microvm-firewall = testMicrovm.mediaCenterFirewallTest;
    microvm-ip-uniqueness = testMicrovm.microvmIpUniquenessTest;
    microvm-ssh = testMicrovm.mediaCenterSshTest;
    microvm-dev-vm-stateversion = testMicrovm.devVmStateVersionTest;

    # LLM client module tests
    llm-client-opencode = testLlmClient.llmClientOpencodeTest;
    llm-client-claude = testLlmClient.llmClientClaudeTest;
    llm-client-pi = testLlmClient.llmClientPiTest;
    llm-client-custom-host = testLlmClient.llmClientCustomHostTest;
    llm-client-no-ai-roles = testLlmClient.llmClientNoAiRolesTest;

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

    # vMLX module tests

    # vllm-mlx module tests
    vllm-mlx-options = testVllmMlx.vllmMlxOptionsTest;
    megamanx-vllm = testVllmMlx.megamanxVllmMlxTest;

    # Claude Code module tests
    claude-code-options = testClaudeCode.claudeCodeOptionsTest;
    claude-code-custom-options = testClaudeCode.claudeCodeCustomOptionsTest;

    # Pi coding agent module tests
    pi-options = testPi.piOptionsTest;
    pi-custom-options = testPi.piCustomOptionsTest;

    # Bifrost AI gateway module tests
    bifrost-options = testBifrost.bifrostOptionsTest;
    bifrost-custom-options = testBifrost.bifrostCustomOptionsTest;

    # Caddy reverse proxy module tests
    caddy-options = testCaddy.caddyOptionsTest;
    caddy-custom-options = testCaddy.caddyCustomOptionsTest;

    # SearXNG module tests
    searxng-options = testSearxng.searxngOptionsTest;
    searxng-custom-options = testSearxng.searxngCustomOptionsTest;

    # Lume module tests
    lume-options = testLume.lumeOptionsTest;
    lume-custom-options = testLume.lumeCustomOptionsTest;

    # LLM stack integration test
    stack-integration = testStackIntegration.stackIntegrationTest;

    # Phase 2: Cattle NixOS v2 configs
    phase2-cattle = testPhase2Cattle.phase2CattleTest;
  }
  // vmTests
