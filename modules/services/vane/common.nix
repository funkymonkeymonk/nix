# Vane AI-powered answering engine - Common configuration
# Vane combines web search (via SearxNG) with LLMs (via Higgs/Ollama/OpenAI)
# to provide accurate answers with cited sources.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.vane;
in {
  options._vaneCommon = mkOption {
    type = types.attrs;
    internal = true;
    description = "Internal: Shared Vane configuration values";
  };

  config._vaneCommon = {
    searxngUrl = cfg.searxngUrl;
    inherit (cfg) port dataDir;
  };
}
