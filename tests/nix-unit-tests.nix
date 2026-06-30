# Unified nix-unit test suite
# Replaces derivation-based option/role tests with a single fast eval.
# Run with: nix-unit ./tests/nix-unit-tests.nix
let
  pkgs = import <nixpkgs> {system = builtins.currentSystem;};
  lib = pkgs.lib;

  # ── Shared stubs ─────────────────────────────────────────────────
  baseStubs = [
    ../modules/common/options.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
      options.environment = {
        systemPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
        };
        variables = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
        sessionVariables = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
        shellAliases = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
        etc = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
        };
      };
      options.programs = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      options.homebrew = lib.mkOption {
        type = lib.types.anything;
        default = {};
      };
      options.users = lib.mkOption {
        type = lib.types.anything;
        default = {};
      };
      options.microvm = lib.mkOption {
        type = lib.types.anything;
        default = {};
      };
      config.microvm.vms = {};
    }
    {config._module.args = {inherit pkgs;};}
  ];

  roleStubs = baseStubs ++ [../modules/roles/default.nix];

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
                entertainment.enable = true;
                agent-skills.enable = true;
                opencode.enable = true;
                claude.enable = true;
                pi.enable = true;
                llm-host.enable = true;
                assistant.enable = true;
                email-backup.enable = true;
                microvm-host.enable = true;
              };
            };
          }
        ];
    }).config;

  evalBase = (lib.evalModules {modules = baseStubs;}).config;

  allRoles = [
    "foundation"
    "developer"
    "creative"
    "gaming"
    "desktop"
    "workstation"
    "entertainment"
    "agent-skills"
    "opencode"
    "claude"
    "pi"
    "llm-host"
    "assistant"
    "email-backup"
    "microvm-host"
    "homebrew"
    "tailscale"
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

  # ── Options: sketchybar ─────────────────────────────────────────
  testSketchybarDefaults = {
    expr = {
      enable = evalBase.myConfig.sketchybar.enable;
      height = evalBase.myConfig.sketchybar.height;
      padding = evalBase.myConfig.sketchybar.padding;
    };
    expected = {
      enable = false;
      height = 40;
      padding = 2;
    };
  };

  testSketchybarCustom = let
    custom =
      (lib.evalModules {
        modules =
          baseStubs
          ++ [
            {
              config.myConfig.sketchybar = {
                enable = true;
                height = 50;
                padding = 8;
                groupPadding = 20;
                useAerospaceIntegration = false;
              };
            }
          ];
      }).config.myConfig.sketchybar;
  in {
    expr = {inherit (custom) enable height padding groupPadding useAerospaceIntegration;};
    expected = {
      enable = true;
      height = 50;
      padding = 8;
      groupPadding = 20;
      useAerospaceIntegration = false;
    };
  };

  # ── Options: aerospace ────────────────────────────────────────
  testAerospaceDefaults = {
    expr = evalBase.myConfig.aerospace.externalMonitor;
    expected = null;
  };

  testAerospaceCustom = let
    custom =
      (lib.evalModules {
        modules =
          baseStubs
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

  # ── Options: jj-autosync ──────────────────────────────────────
  testJjAutosyncDefaults = {
    expr = {
      enable = evalBase.myConfig.jj-autosync.enable;
      fastSyncInterval = evalBase.myConfig.jj-autosync.fastSyncInterval;
    };
    expected = {
      enable = false;
      fastSyncInterval = 300;
    };
  };

  testJjAutosyncCustom = let
    custom =
      (lib.evalModules {
        modules =
          baseStubs
          ++ [
            {
              config.myConfig.jj-autosync = {
                enable = true;
                username = "test";
                fastSyncInterval = 60;
              };
            }
          ];
      }).config.myConfig.jj-autosync;
  in {
    expr = {inherit (custom) enable username fastSyncInterval;};
    expected = {
      enable = true;
      username = "test";
      fastSyncInterval = 60;
    };
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

  # ── Options: vane ─────────────────────────────────────────────
  testVaneDefaults = {
    expr = {
      enable = evalBase.myConfig.vane.enable;
      port = evalBase.myConfig.vane.port;
      defaultModel = evalBase.myConfig.vane.defaultModel;
    };
    expected = {
      enable = false;
      port = 3000;
      defaultModel = "deepseek-r1:14b";
    };
  };

  testVaneCustom = let
    custom =
      (lib.evalModules {
        modules =
          baseStubs
          ++ [
            {
              config.myConfig.vane = {
                enable = true;
                port = 8080;
                openaiBaseUrl = "http://custom:8080";
                defaultModel = "custom-model";
              };
            }
          ];
      }).config.myConfig.vane;
  in {
    expr = {inherit (custom) enable port openaiBaseUrl defaultModel;};
    expected = {
      enable = true;
      port = 8080;
      openaiBaseUrl = "http://custom:8080";
      defaultModel = "custom-model";
    };
  };

  # ── Options: 1Password ────────────────────────────────────────
  testOnepasswordDefaults = {
    expr = {
      enable = evalBase.myConfig.onepassword.enable;
      enableSSHAgent = evalBase.myConfig.onepassword.enableSSHAgent;
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
    expr = evalBase.myConfig.caddy.enable;
    expected = false;
  };

  # ── Options: bifrost ──────────────────────────────────────────
  testBifrostDefaults = {
    expr = {
      enable = evalBase.myConfig.bifrost.enable;
      port = evalBase.myConfig.bifrost.port;
    };
    expected = {
      enable = false;
      port = 8081;
    };
  };

  # ── Options: searxng ────────────────────────────────────────────
  testSearxngDefaults = {
    expr = evalBase.myConfig.searxng.enable;
    expected = false;
  };

  # ── Options: fjj ────────────────────────────────────────────────
  testFjjDefaults = {
    expr = evalBase.myConfig.fjj.enable;
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

  # ── Options: microvm ────────────────────────────────────────────
  testMicrovmDefaults = {
    expr = {
      enable = evalBase.myConfig.microvm.enable;
      ipAddress = evalBase.myConfig.microvm.ipAddress;
      gateway = evalBase.myConfig.microvm.gateway;
    };
    expected = {
      enable = false;
      ipAddress = null;
      gateway = null;
    };
  };

  # ── Options: zellij ─────────────────────────────────────────────
  testZellijDefaults = {
    expr = evalBase.myConfig.zellij.enable;
    expected = false;
  };

  # ── Options: agent-skills ─────────────────────────────────────
  testSkillsDefaults = {
    expr = evalBase.myConfig.agent-skills.enable;
    expected = false;
  };
}
