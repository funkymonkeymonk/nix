# email-agent module: Agent tools for Gmail interaction
#
# Provides:
# - email-filters: gmailctl wrapper for declarative Gmail filter management
# - himalaya: CLI email client (installed by assistant role, configured here)
#
# These tools operate directly on Gmail — no local duplication.
# For immutable backups, see the email-backup module.
#
# Authentication:
# - gmailctl: OAuth2 via 'email-filters init' (one-time interactive setup)
# - himalaya: Uses Gmail App Password or OAuth2 (configured in ~/.config/himalaya/config.toml)
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
with lib; let
  cfg =
    osConfig.myConfig.email-agent
    or config.myConfig.email-agent
    or {};
  enabled = cfg.enable or false;
  enableGmailctl = cfg.enableGmailctl or true;
  gmailctlConfigDir = cfg.gmailctlConfigDir or ".config/gmailctl";

  # Gmail filter helper — wraps gmailctl for agent use.
  # Script body lives in email-agent/email-filters.sh so it gets proper
  # bash syntax highlighting and can be shellchecked directly.
  emailFiltersContent =
    lib.replaceStrings
    ["__GMAILCTL_CONFIG_DIR__"]
    [gmailctlConfigDir]
    (builtins.readFile ./email-agent/email-filters.sh);
in {
  config = mkIf enabled {
    home.packages =
      optional enableGmailctl (pkgs.writeShellScriptBin "email-filters" emailFiltersContent);
  };
}
