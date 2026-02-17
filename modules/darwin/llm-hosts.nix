{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig;
in {
  config = lib.mkIf (builtins.length cfg.users == 1) {
    home-manager.users.${(builtins.head cfg.users).name}.home.sessionVariables = {
      LITELLM_HOST = "http://localhost:4000";
      OLLAMA_HOST = "http://localhost:11434";
    };
  };
}
