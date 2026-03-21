{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.onepassword;
  isDarwin = builtins.elem pkgs.system ["aarch64-darwin" "x86_64-darwin"];

  # 1Password SSH agent socket path differs by platform
  sshAgentPath =
    if isDarwin
    then "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else "~/.1password/agent.sock";
in {
  config = mkIf cfg.enable {
    # Install 1Password CLI on NixOS
    programs._1password = mkIf (!isDarwin) {
      enable = true;
      package = pkgs._1password-cli;
    };

    # Install 1Password GUI on NixOS for SSH agent and GUI functionality
    programs._1password-gui = mkIf (!isDarwin) {
      enable = true;
      package = pkgs._1password-gui;
      # Enable polkit for sudo integration
      polkitPolicyOwners = map (user: user.name) config.myConfig.users;
    };

    # Enable 1Password SSH agent on all platforms
    programs.ssh.extraConfig = mkIf cfg.enableSSHAgent ''
      # Use 1Password as SSH agent
      IdentityAgent "${sshAgentPath}"
    '';

    # Set SSH_AUTH_SOCK environment variable for applications
    environment.sessionVariables = mkIf cfg.enableSSHAgent {
      SSH_AUTH_SOCK = sshAgentPath;
    };

    # Configure sudo to use 1Password for authentication (NixOS only)
    # This requires setting up a PAM module or sudoers configuration
    security.sudo.extraConfig = mkIf (cfg.enableSudo && !isDarwin) ''
      # Allow 1Password authentication for sudo
      Defaults env_keep += "OP_BIOMETRIC_UNLOCKED"
    '';
  };
}
