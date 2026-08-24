# myConfig.email-agent options — owned here, consumed by
# modules/home-manager/email-agent.nix (loaded conditionally via
# modules/common/users.nix) and set by modules/roles/assistant.nix.
{lib, ...}: {
  options.myConfig.email-agent = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable agent email tools (himalaya CLI, gmailctl filters)";
    };

    enableGmailctl = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable gmailctl for declarative Gmail filter management. Requires one-time OAuth2 setup via 'email-filters init'.";
    };

    gmailctlConfigDir = lib.mkOption {
      type = lib.types.str;
      default = ".config/gmailctl";
      description = "Path relative to home directory for gmailctl configuration (Jsonnet filter definitions)";
    };
  };
}
