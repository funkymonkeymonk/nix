# LLM host role — provides ollama for local LLM hosting
#
# Note: ollama itself is installed by modules/services/ollama/darwin.nix
#       via homebrew. This role exists only to enable the service option.
{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.roles.llm-host;
in {
  config = lib.mkIf cfg.enable {
    myConfig.ollama.enable = true;
  };
}
