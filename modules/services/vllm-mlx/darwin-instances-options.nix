# Defines the option for additional vllm-mlx instances.
{lib, ...}: {
  options.myConfig.vllmMlxInstances = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule (import ./instance-options.nix));
    default = {};
    description = "Additional named vllm-mlx instances. Each instance gets its own launchd daemon, log directory, and port.";
  };
}
