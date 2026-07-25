# LLM host role — provides ollama for local LLM hosting
#
# Note: ollama itself is installed by modules/services/ollama/darwin.nix
#       via homebrew. This role exists only to enable the service option.
{
  config,
  options,
  lib,
  ...
}: let
  cfg = config.myConfig.roles.llm-host;
  # myConfig.ollama is declared by modules/services/ollama/darwin.nix, which
  # is only imported on hosts that actually run it (see library/archetypes/
  # workstation-darwin.nix). Guard with hasAttr so this role is a safe no-op
  # on hosts (e.g. darwin-server) that don't import that module at all.
  hasOllamaOption = builtins.hasAttr "ollama" options.myConfig;
in {
  config = lib.optionalAttrs hasOllamaOption (lib.mkIf cfg.enable {
    myConfig.ollama.enable = true;
  });
}
