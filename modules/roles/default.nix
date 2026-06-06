# Role modules — import all roles and compute enabledRoles for skills
{config, ...}: let
  roleNames = builtins.attrNames config.myConfig.roles;
  enabledRoles =
    builtins.filter (
      name: config.myConfig.roles.${name}.enable
    )
    roleNames;
in {
  imports = [
    ./foundation.nix
    ./developer.nix
    ./creative.nix
    ./gaming.nix
    ./desktop.nix
    ./workstation.nix
    ./entertainment.nix
    ./agent-skills.nix
    ./opencode.nix
    ./claude.nix
    ./pi.nix
    ./assistant.nix
    ./email-backup.nix
    ./llm-host.nix
    ./microvm-host.nix
    ./tailscale.nix
    # Note: homebrew.nix is imported separately by configurations that use nix-homebrew
  ];

  # Derive enabledRoles from the roles options so skills/install.nix can use it
  config.myConfig.skills.enabledRoles = enabledRoles;
}
