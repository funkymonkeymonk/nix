# Shared LLM client environment variables
# Sets LLM_SERVER_HOST, LLM_SERVER_PORT, OPENCODE_ENDPOINT, and CLAUDE_API_BASE
# when any AI agent role (claude, opencode, pi) is enabled.
{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.llmClient;
  anyAiRoleActive =
    config.myConfig.roles.claude.enable
    || config.myConfig.roles.opencode.enable
    || config.myConfig.roles.pi.enable;
in {
  config = lib.mkIf anyAiRoleActive {
    environment.variables = {
      LLM_SERVER_HOST = cfg.serverHost;
      LLM_SERVER_PORT = cfg.serverPort;
      OPENCODE_ENDPOINT = "http://${cfg.serverHost}:${cfg.serverPort}";
      CLAUDE_API_BASE = "http://${cfg.serverHost}:${cfg.serverPort}";
    };
  };
}
