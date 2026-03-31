# wweaver (work laptop) target configuration
# Machine-specific settings go here
{lib, ...}: {
  # Work laptop specific configuration
  # Most config comes from roles and mkUser

  # Ollama configuration for local models
  # Smaller/faster models for quick tasks, LiteLLM handles heavy workloads
  myConfig.ollama = {
    models = lib.mkForce ["qwen3.5:2b" "qwen3.5"];
  };
}
