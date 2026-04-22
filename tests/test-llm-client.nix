# LLM client module tests
# Verifies that modules/common/llm-client.nix sets the correct environment
# variables when any AI agent role is enabled.
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Stub modules for evalModules - provide options needed by roles
  stubModules = [
    ../modules/common/options.nix
    ../modules/common/llm-client.nix
    ../modules/roles/default.nix
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
      options.microvm = lib.mkOption {
        type = lib.types.anything;
        default = {};
      };
      config.microvm.vms = {};
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  # Helper: evaluate with a given role enabled
  evalWithRole = roleName:
    (lib.evalModules {
      modules =
        stubModules
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
              roles.${roleName}.enable = true;
            };
          }
        ];
    })
    .config;

  # Evaluate with custom llmClient settings and opencode role enabled
  evalWithCustomHost =
    (lib.evalModules {
      modules =
        stubModules
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
              roles.opencode.enable = true;
              llmClient = {
                serverHost = "192.168.1.100";
                serverPort = "11435";
              };
            };
          }
        ];
    })
    .config;

  # Evaluate with NO AI roles enabled - env vars should NOT be set
  evalWithNoAiRoles =
    (lib.evalModules {
      modules =
        stubModules
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
              roles.developer.enable = true;
            };
          }
        ];
    })
    .config;

  opencodeVars = evalWithRole "opencode";
  claudeVars = evalWithRole "claude";
  piVars = evalWithRole "pi";
  customVars = evalWithCustomHost;
  noAiVars = evalWithNoAiRoles;

  defaultExpectedHost = "127.0.0.1";
  defaultExpectedPort = "11434";
  defaultExpectedEndpoint = "http://127.0.0.1:11434";
in {
  # Test that LLM_SERVER_HOST and LLM_SERVER_PORT are set when opencode role is enabled
  llmClientOpencodeTest =
    pkgs.runCommand "test-llm-client-opencode"
    {}
    ''
      echo "=== Testing llm-client env vars with opencode role ==="

      ${
        if opencodeVars.environment.variables.LLM_SERVER_HOST or null == defaultExpectedHost
        then ''echo "  LLM_SERVER_HOST set correctly for opencode: OK"''
        else ''
          echo "  FAIL: LLM_SERVER_HOST not set correctly for opencode role"
          echo "  expected: ${defaultExpectedHost}"
          echo "  got: ${opencodeVars.environment.variables.LLM_SERVER_HOST or "NOT SET"}"
          exit 1
        ''
      }

      ${
        if opencodeVars.environment.variables.LLM_SERVER_PORT or null == defaultExpectedPort
        then ''echo "  LLM_SERVER_PORT set correctly for opencode: OK"''
        else ''
          echo "  FAIL: LLM_SERVER_PORT not set correctly for opencode role"
          echo "  expected: ${defaultExpectedPort}"
          echo "  got: ${opencodeVars.environment.variables.LLM_SERVER_PORT or "NOT SET"}"
          exit 1
        ''
      }

      ${
        if opencodeVars.environment.variables.OPENCODE_ENDPOINT or null == defaultExpectedEndpoint
        then ''echo "  OPENCODE_ENDPOINT set correctly for opencode: OK"''
        else ''
          echo "  FAIL: OPENCODE_ENDPOINT not set correctly for opencode role"
          echo "  expected: ${defaultExpectedEndpoint}"
          echo "  got: ${opencodeVars.environment.variables.OPENCODE_ENDPOINT or "NOT SET"}"
          exit 1
        ''
      }

      ${
        if opencodeVars.environment.variables.CLAUDE_API_BASE or null == defaultExpectedEndpoint
        then ''echo "  CLAUDE_API_BASE set correctly for opencode: OK"''
        else ''
          echo "  FAIL: CLAUDE_API_BASE not set correctly for opencode role"
          echo "  expected: ${defaultExpectedEndpoint}"
          echo "  got: ${opencodeVars.environment.variables.CLAUDE_API_BASE or "NOT SET"}"
          exit 1
        ''
      }

      echo "All llm-client opencode tests passed"
      touch $out
    '';

  # Test that env vars are set when claude role is enabled
  llmClientClaudeTest =
    pkgs.runCommand "test-llm-client-claude"
    {}
    ''
      echo "=== Testing llm-client env vars with claude role ==="

      ${
        if claudeVars.environment.variables.LLM_SERVER_HOST or null == defaultExpectedHost
        then ''echo "  LLM_SERVER_HOST set correctly for claude: OK"''
        else ''
          echo "  FAIL: LLM_SERVER_HOST not set correctly for claude role"
          exit 1
        ''
      }

      ${
        if claudeVars.environment.variables.LLM_SERVER_PORT or null == defaultExpectedPort
        then ''echo "  LLM_SERVER_PORT set correctly for claude: OK"''
        else ''
          echo "  FAIL: LLM_SERVER_PORT not set correctly for claude role"
          exit 1
        ''
      }

      ${
        if claudeVars.environment.variables.OPENCODE_ENDPOINT or null == defaultExpectedEndpoint
        then ''echo "  OPENCODE_ENDPOINT set correctly for claude: OK"''
        else ''
          echo "  FAIL: OPENCODE_ENDPOINT not set correctly for claude role"
          exit 1
        ''
      }

      ${
        if claudeVars.environment.variables.CLAUDE_API_BASE or null == defaultExpectedEndpoint
        then ''echo "  CLAUDE_API_BASE set correctly for claude: OK"''
        else ''
          echo "  FAIL: CLAUDE_API_BASE not set correctly for claude role"
          exit 1
        ''
      }

      echo "All llm-client claude tests passed"
      touch $out
    '';

  # Test that LLM_SERVER_HOST and LLM_SERVER_PORT are set when pi role is enabled
  # (pi does NOT set OPENCODE_ENDPOINT or CLAUDE_API_BASE)
  llmClientPiTest =
    pkgs.runCommand "test-llm-client-pi"
    {}
    ''
      echo "=== Testing llm-client env vars with pi role ==="

      ${
        if piVars.environment.variables.LLM_SERVER_HOST or null == defaultExpectedHost
        then ''echo "  LLM_SERVER_HOST set correctly for pi: OK"''
        else ''
          echo "  FAIL: LLM_SERVER_HOST not set correctly for pi role"
          exit 1
        ''
      }

      ${
        if piVars.environment.variables.LLM_SERVER_PORT or null == defaultExpectedPort
        then ''echo "  LLM_SERVER_PORT set correctly for pi: OK"''
        else ''
          echo "  FAIL: LLM_SERVER_PORT not set correctly for pi role"
          exit 1
        ''
      }

      echo "All llm-client pi tests passed"
      touch $out
    '';

  # Test that custom host/port are reflected in env vars
  llmClientCustomHostTest =
    pkgs.runCommand "test-llm-client-custom-host"
    {}
    ''
      echo "=== Testing llm-client with custom serverHost/serverPort ==="

      ${
        if customVars.environment.variables.LLM_SERVER_HOST or null == "192.168.1.100"
        then ''echo "  LLM_SERVER_HOST reflects custom host: OK"''
        else ''
          echo "  FAIL: LLM_SERVER_HOST should be 192.168.1.100"
          echo "  got: ${customVars.environment.variables.LLM_SERVER_HOST or "NOT SET"}"
          exit 1
        ''
      }

      ${
        if customVars.environment.variables.LLM_SERVER_PORT or null == "11435"
        then ''echo "  LLM_SERVER_PORT reflects custom port: OK"''
        else ''
          echo "  FAIL: LLM_SERVER_PORT should be 11435"
          echo "  got: ${customVars.environment.variables.LLM_SERVER_PORT or "NOT SET"}"
          exit 1
        ''
      }

      ${
        if customVars.environment.variables.OPENCODE_ENDPOINT or null == "http://192.168.1.100:11435"
        then ''echo "  OPENCODE_ENDPOINT uses custom host/port: OK"''
        else ''
          echo "  FAIL: OPENCODE_ENDPOINT should be http://192.168.1.100:11435"
          echo "  got: ${customVars.environment.variables.OPENCODE_ENDPOINT or "NOT SET"}"
          exit 1
        ''
      }

      ${
        if customVars.environment.variables.CLAUDE_API_BASE or null == "http://192.168.1.100:11435"
        then ''echo "  CLAUDE_API_BASE uses custom host/port: OK"''
        else ''
          echo "  FAIL: CLAUDE_API_BASE should be http://192.168.1.100:11435"
          echo "  got: ${customVars.environment.variables.CLAUDE_API_BASE or "NOT SET"}"
          exit 1
        ''
      }

      echo "All llm-client custom host tests passed"
      touch $out
    '';

  # Test that env vars are NOT set when no AI roles are enabled
  llmClientNoAiRolesTest =
    pkgs.runCommand "test-llm-client-no-ai-roles"
    {}
    ''
      echo "=== Testing llm-client env vars absent when no AI role enabled ==="

      ${
        if noAiVars.environment.variables ? LLM_SERVER_HOST
        then ''
          echo "  FAIL: LLM_SERVER_HOST should NOT be set when no AI role enabled"
          exit 1
        ''
        else ''echo "  LLM_SERVER_HOST correctly absent: OK"''
      }

      ${
        if noAiVars.environment.variables ? LLM_SERVER_PORT
        then ''
          echo "  FAIL: LLM_SERVER_PORT should NOT be set when no AI role enabled"
          exit 1
        ''
        else ''echo "  LLM_SERVER_PORT correctly absent: OK"''
      }

      echo "All llm-client no-ai-roles tests passed"
      touch $out
    '';
}
