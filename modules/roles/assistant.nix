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
    description = "Agent email tools (himalaya, gmailctl) for reading, moving, and filtering Gmail";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      himalaya # CLI email client for agent scripting
      gmailctl # Declarative Gmail filter management
    ];

    myConfig.email-agent.enable = true;
  };
}
