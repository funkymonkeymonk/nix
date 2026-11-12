# Assistant role - agent email tools (direct Gmail access)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.assistant;
in {
  options.myConfig.roles.assistant.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Gmail filter management tools for email agents";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gmailctl # Declarative Gmail filter management
    ];

    myConfig.email-agent.enable = true;
  };
}
