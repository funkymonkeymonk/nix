# Unified nix-unit test suite
# Replaces derivation-based option/role tests with a single fast eval.
# Run with: nix-unit ./tests/nix-unit-tests.nix
let
  pkgs = import <nixpkgs> {system = builtins.currentSystem;};
  lib = pkgs.lib;

  # ── Shared stubs (from tests/stubs.nix) ──────────────────────────
  stubs = import ./stubs.nix {inherit pkgs;};

  # Convenience aliases matching the old local names so test expressions
  # below don't need to change.
  baseStubs = stubs.base;
  roleStubs = stubs.withRoles;

  evalAllRoles =
    (lib.evalModules {
      modules =
        roleStubs
        ++ [
          {
            config.myConfig = {
              users = [
                {
                  name = "testuser";
                  email = "test@example.com";
                  fullName = "Test User";
                  isAdmin = true;
                  sshIncludes = [];
                }
              ];
              roles = {
                foundation.enable = true;
                developer.enable = true;
                creative.enable = true;
                gaming.enable = true;
                desktop.enable = true;
                workstation.enable = true;
                work.enable = true;
                entertainment.enable = true;
                agent-skills.enable = true;
                opencode.enable = true;
                claude.enable = true;
                pi.enable = true;
                assistant.enable = true;
                email-backup.enable = true;
              };
            };
          }
        ];
    }).config;

  evalBase = (lib.evalModules {modules = baseStubs;}).config;

  searxngStubs = stubs.searxng;
  bifrostStubs = stubs.bifrost;
  caddyStubs = stubs.caddy;
  onepasswordStubs = baseStubs ++ stubs.onepassword;
  agentSkillsStubs = stubs.agentSkills;
  # aerospace.nix lives under modules/home-manager/ but is imported at the
  # host-module level (services.aerospace, environment.systemPackages), not
  # inside a home-manager users.<name> block — see flake.nix.
  aerospaceStubs = stubs.aerospace;

  evalSearxngBase = (lib.evalModules {modules = searxngStubs;}).config;
  evalBifrostBase = (lib.evalModules {modules = bifrostStubs;}).config;
  evalCaddyBase = (lib.evalModules {modules = caddyStubs;}).config;
  evalOnepasswordBase = (lib.evalModules {modules = onepasswordStubs;}).config;
  evalAgentSkillsBase = (lib.evalModules {modules = agentSkillsStubs;}).config;
  evalAerospaceBase = (lib.evalModules {modules = aerospaceStubs;}).config;

  # Shared library helpers for unit testing extracted functions
  commonLib = import ../modules/common/lib.nix {inherit lib;};

  allRoles = [
    "foundation"
    "developer"
    "creative"
    "gaming"
    "desktop"
    "workstation"
    "work"
    "entertainment"
    "agent-skills"
    "opencode"
    "claude"
    "pi"
    "assistant"
    "email-backup"
    "homebrew"
  ];
in {
  # ── Role definitions ────────────────────────────────────────────
  testRoleDefinitions = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames evalAllRoles.myConfig.roles);
    expected = builtins.sort builtins.lessThan allRoles;
  };

  testFoundationDefault = {
    expr = evalBase.myConfig.roles.foundation.enable;
    expected = true;
  };

  # ── Options: aerospace ────────────────────────────────────────
  testAerospaceDefaults = {
    expr = evalAerospaceBase.myConfig.aerospace.externalMonitor;
    expected = null;
  };

  testAerospaceCustom = let
    custom =
      (lib.evalModules {
        modules =
          aerospaceStubs
          ++ [
            {
              config.myConfig.aerospace = {externalMonitor = "TEST";};
            }
          ];
      }).config.myConfig.aerospace;
  in {
    expr = custom.externalMonitor;
    expected = "TEST";
  };

  # ── Options: opencode ───────────────────────────────────────────
  testOpencodeDefaults = {
    expr = {
      enable = evalBase.myConfig.opencode.enable;
      model = evalBase.myConfig.opencode.model;
    };
    expected = {
      enable = false;
      model = null;
    };
  };

  testOpencodeCustom = let
    custom =
      (lib.evalModules {
        modules =
          baseStubs
          ++ [
            {
              config.myConfig.opencode = {
                enable = true;
                model = "anthropic/claude-sonnet-4";
              };
            }
          ];
      }).config.myConfig.opencode;
  in {
    expr = {inherit (custom) enable model;};
    expected = {
      enable = true;
      model = "anthropic/claude-sonnet-4";
    };
  };

  # ── Options: 1Password ────────────────────────────────────────
  testOnepasswordDefaults = {
    expr = {
      enable = evalOnepasswordBase.myConfig.onepassword.enable;
      enableSSHAgent = evalOnepasswordBase.myConfig.onepassword.enableSSHAgent;
    };
    expected = {
      enable = true;
      enableSSHAgent = true;
    };
  };

  # ── Options: email ────────────────────────────────────────────
  testEmailBackupDefaults = {
    expr = evalBase.myConfig.email-backup.enable;
    expected = false;
  };

  # ── Options: llm-client ────────────────────────────────────────
  testLlmClientDefaults = {
    expr = evalBase.myConfig.llmClient.rtk.enable;
    expected = false;
  };

  # ── Options: caddy ──────────────────────────────────────────────
  testCaddyDefaults = {
    expr = evalCaddyBase.myConfig.caddy.enable;
    expected = false;
  };

  # ── Options: bifrost ──────────────────────────────────────────
  testBifrostDefaults = {
    expr = {
      enable = evalBifrostBase.myConfig.bifrost.enable;
      port = evalBifrostBase.myConfig.bifrost.port;
    };
    expected = {
      enable = false;
      port = 8081;
    };
  };

  # ── Options: searxng ────────────────────────────────────────────
  testSearxngDefaults = {
    expr = evalSearxngBase.myConfig.searxng.enable;
    expected = false;
  };

  # ── Options: pi ─────────────────────────────────────────────────
  testPiDefaults = {
    expr = evalBase.myConfig.pi.enable;
    expected = false;
  };

  # ── Options: claude-code ────────────────────────────────────────
  testClaudeCodeDefaults = {
    expr = evalBase.myConfig.claude-code.enable;
    expected = false;
  };

  # ── Options: zellij ─────────────────────────────────────────────
  testZellijDefaults = {
    expr = evalBase.myConfig.zellij.enable;
    expected = false;
  };

  # ── Options: agent-skills ─────────────────────────────────────
  testSkillsDefaults = {
    expr = evalAgentSkillsBase.myConfig.agent-skills.enable;
    expected = false;
  };

  # ── Shared library: common/lib.nix helpers ────────────────────────

  # darwinUserEnv with users configured
  testDarwinUserEnvWithUsers = let
    alice = {
      name = "alice";
      email = "a@b.com";
      sshIncludes = [];
    };
    config = {myConfig.users = [alice];};
    result = commonLib.darwinUserEnv config;
  in {
    expr = result;
    expected = {
      name = "alice";
      home = "/Users/alice";
    };
  };

  # darwinUserEnv with no users falls back to root
  testDarwinUserEnvNoUsers = let
    config = {myConfig.users = [];};
    result = commonLib.darwinUserEnv config;
  in {
    expr = result;
    expected = {
      name = "root";
      home = "/Users/root";
    };
  };

  # primaryUser convenience wrapper
  testPrimaryUser = let
    bob = {
      name = "bob";
      email = "b@b.com";
      sshIncludes = [];
    };
    config = {myConfig.users = [bob];};
    result = commonLib.primaryUser config;
  in {
    expr = result;
    expected = "bob";
  };

  # darwinHomeDir convenience wrapper
  testDarwinHomeDir = let
    carol = {
      name = "carol";
      email = "c@b.com";
      sshIncludes = [];
    };
    config = {myConfig.users = [carol];};
    result = commonLib.darwinHomeDir config;
  in {
    expr = result;
    expected = "/Users/carol";
  };

  # mkServiceRegistry: enabled service produces entry
  testServiceRegistryEnabled = {
    expr = commonLib.mkServiceRegistry "bifrost" {
      displayName = "Bifrost";
      port = 8081;
      label = "org.nixos.bifrost";
      errorLog = "/var/log/bifrost-error.log";
      enabled = true;
    };
    expected = {
      bifrost = {
        name = "Bifrost";
        port = 8081;
        launchdLabel = "org.nixos.bifrost";
        errorLog = "/var/log/bifrost-error.log";
      };
    };
  };

  # mkServiceRegistry: disabled service produces empty attrset
  testServiceRegistryDisabled = {
    expr = commonLib.mkServiceRegistry "omlx" {
      displayName = "oMLX";
      port = 8300;
      label = "org.omlx.server";
      errorLog = "/var/log/omlx-error.log";
      enabled = false;
    };
    expected = {};
  };

  # mkServiceRegistry: multiple services composed
  testServiceRegistryComposition = let
    svc1 = commonLib.mkServiceRegistry "svc-a" {
      displayName = "Svc A";
      port = 80;
      label = "org.nixos.svc-a";
      errorLog = "/var/log/svc-a.log";
      enabled = true;
    };
    svc2 = commonLib.mkServiceRegistry "svc-b" {
      displayName = "Svc B";
      port = 443;
      label = "org.nixos.svc-b";
      errorLog = "/var/log/svc-b.log";
      enabled = true;
    };
    svc3 = commonLib.mkServiceRegistry "svc-off" {
      displayName = "Svc Off";
      port = 999;
      label = "org.nixos.svc-off";
      errorLog = "/var/log/svc-off.log";
      enabled = false;
    };
    combined = lib.recursiveUpdate svc1 (lib.recursiveUpdate svc2 svc3);
  in {
    expr = {keys = builtins.sort builtins.lessThan (builtins.attrNames combined);};
    expected = {keys = ["svc-a" "svc-b"];};
  };
}
