{pkgs, ...}: let
  # Create proper executable scripts in the nix store
  switch-nix-script = pkgs.writeShellScriptBin "switch-nix" (builtins.readFile ./scripts/switch-nix);
  nix-cloud-init-script = pkgs.writeShellScriptBin "nix-cloud-init" (builtins.readFile ./scripts/nix-cloud-init);
in {
  # System-level shell configuration
  # This module handles global shell setup that applies to all users

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # System-wide zsh init - works on both NixOS and Darwin
  programs.zsh.interactiveShellInit = ''
    export SHELL=${pkgs.zsh}/bin/zsh

    # Source switch-nix function
    if [ -f ${switch-nix-script}/bin/switch-nix ]; then
      . ${switch-nix-script}/bin/switch-nix
    fi
  '';

  # Make scripts available in PATH
  environment.systemPackages = [
    switch-nix-script
    nix-cloud-init-script
  ];

  # Also install to /etc for reference
  environment.etc."nix-cloud-init/switch-nix".source = "${switch-nix-script}/bin/switch-nix";
  environment.etc."nix-cloud-init/nix-cloud-init".source = "${nix-cloud-init-script}/bin/nix-cloud-init";
}
