# Agent user module tests
# Validates option defaults and custom values from modules/common/agent-user.nix
{pkgs, ...}: let
  inherit (pkgs) lib;

  agentUserStubs = [
    ../modules/common/agent-user.nix
    {
      options.users.users = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      options.users.groups = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
    }
  ];

  agentUserDefaults =
    (lib.evalModules {
      modules = agentUserStubs;
    }).config.myConfig.agentUser;

  agentUserDisabledEval =
    (lib.evalModules {
      modules = agentUserStubs;
    }).config;

  agentUserEnabledEval =
    (lib.evalModules {
      modules =
        agentUserStubs
        ++ [
          {
            config.myConfig.agentUser.enable = true;
          }
        ];
    }).config;

  agentUserCustomEval =
    (lib.evalModules {
      modules =
        agentUserStubs
        ++ [
          {
            config.myConfig.agentUser = {
              enable = true;
              name = "customagent";
              home = "/var/lib/customagent";
              uid = 999;
              gid = 999;
            };
          }
        ];
    }).config;
in {
  # Test default option values
  agentUserOptionsTest =
    pkgs.runCommand "test-agent-user-options"
    {}
    ''
      echo "=== Testing Agent User Option Defaults ==="

      ${
        if !agentUserDefaults.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if agentUserDefaults.name == "agent"
        then ''echo "  name default = agent: OK"''
        else ''echo "  name should default to agent!"; exit 1''
      }

      ${
        if agentUserDefaults.home == "/var/lib/agent"
        then ''echo "  home default = /var/lib/agent: OK"''
        else ''echo "  home should default to /var/lib/agent!"; exit 1''
      }

      ${
        if agentUserDefaults.uid == null
        then ''echo "  uid default = null (auto-assigned): OK"''
        else ''echo "  uid should default to null!"; exit 1''
      }

      ${
        if agentUserDefaults.gid == null
        then ''echo "  gid default = null (auto-assigned): OK"''
        else ''echo "  gid should default to null!"; exit 1''
      }

      echo "All agent-user option defaults verified"
      touch $out
    '';

  # Test that disabling the agent user produces no users.users/users.groups entries
  agentUserDisabledTest =
    pkgs.runCommand "test-agent-user-disabled"
    {}
    ''
      echo "=== Testing Agent User Disabled (default) ==="

      ${
        if agentUserDisabledEval.users.users == {}
        then ''echo "  users.users empty when disabled: OK"''
        else ''echo "  FAIL: users.users should be empty when agentUser is disabled"; exit 1''
      }

      echo "agent-user disabled test passed"
      touch $out
    '';

  # Test that enabling creates the expected user with security-relevant
  # defaults (no sudo access via empty extraGroups, isSystemUser, createHome)
  agentUserEnabledTest =
    pkgs.runCommand "test-agent-user-enabled"
    {}
    ''
      echo "=== Testing Agent User Enabled (defaults) ==="

      ${
        let
          userCfg = agentUserEnabledEval.users.users.agent or null;
        in
          if userCfg != null
          then ''echo "  users.users.agent created: OK"''
          else ''echo "  FAIL: users.users.agent should exist when agentUser.enable = true"; exit 1''
      }

      ${
        let
          userCfg = agentUserEnabledEval.users.users.agent;
        in
          if userCfg.isSystemUser
          then ''echo "  agent is a system user: OK"''
          else ''echo "  FAIL: agent should be a system user"; exit 1''
      }

      ${
        let
          userCfg = agentUserEnabledEval.users.users.agent;
        in
          if userCfg.createHome
          then ''echo "  agent home directory is created: OK"''
          else ''echo "  FAIL: agent should have createHome = true"; exit 1''
      }

      ${
        let
          userCfg = agentUserEnabledEval.users.users.agent;
        in
          if userCfg.extraGroups == []
          then ''echo "  agent has NO extra groups (no sudo access): OK"''
          else ''echo "  FAIL: agent should have empty extraGroups (security guarantee), got [${builtins.concatStringsSep ", " userCfg.extraGroups}]"; exit 1''
      }

      ${
        let
          userCfg = agentUserEnabledEval.users.users.agent;
        in
          if userCfg.group == "agent"
          then ''echo "  agent's group matches its name: OK"''
          else ''echo "  FAIL: agent's group should be 'agent'"; exit 1''
      }

      echo "agent-user enabled test passed"
      touch $out
    '';

  # Test custom name/home/uid/gid are respected
  agentUserCustomTest =
    pkgs.runCommand "test-agent-user-custom"
    {}
    ''
      echo "=== Testing Agent User Custom Values ==="

      ${
        let
          userCfg = agentUserCustomEval.users.users.customagent or null;
        in
          if userCfg != null
          then ''echo "  users.users.customagent created: OK"''
          else ''echo "  FAIL: users.users.customagent should exist with a custom name"; exit 1''
      }

      ${
        let
          userCfg = agentUserCustomEval.users.users.customagent;
        in
          if userCfg.home == "/var/lib/customagent"
          then ''echo "  custom home respected: OK"''
          else ''echo "  FAIL: custom home should be /var/lib/customagent"; exit 1''
      }

      ${
        let
          userCfg = agentUserCustomEval.users.users.customagent;
        in
          if userCfg.uid == 999
          then ''echo "  custom uid respected: OK"''
          else ''echo "  FAIL: custom uid should be 999"; exit 1''
      }

      ${
        let
          groupCfg = agentUserCustomEval.users.groups.customagent or null;
        in
          if groupCfg != null && groupCfg.gid == 999
          then ''echo "  custom gid respected: OK"''
          else ''echo "  FAIL: users.groups.customagent.gid should be 999"; exit 1''
      }

      echo "agent-user custom values test passed"
      touch $out
    '';
}
