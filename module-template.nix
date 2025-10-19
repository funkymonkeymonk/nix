{
  config,
  pkgs,
  lib,
  ...
}:
# Per-machine NixOS module template for this repository.
#
# Usage:
# - Copy this file to `nix/<machine>.nix` and reference it from `flake.nix`
#   (add to the machine's `modules` list in `nixosConfigurations`).
# - Use `${pkgs.<pkg>}` when embedding Nix package paths into files managed
#   by Nix (these are resolved at evaluation time). Use `$HOME` (not
#   `${HOME}`) inside shell/text literals when you need the runtime user's
#   home directory.
#
# Common gotcha: `${HOME}` inside a Nix string will be interpreted by the
# Nix evaluator and typically causes errors. Prefer `$HOME` in runtime
# shells/scripts and `${pkgs.<pkg>}` for Nix package paths.
{
  # Example user entry — replace <username> and the fields below.
  users.users."<username>" = {
    isNormalUser = true;
    description = "<description>";
    extraGroups = ["wheel" "networkmanager"];
    # Use the shell from nixpkgs so the login shell path exists and is managed.
    shell = pkgs.zsh;
    # Optional explicit home; Nix will normally set a sensible default.
    # home = "/home/<username>";
  };

  # Ensure the package is available system-wide so paths like ${pkgs.zsh}
  # reference a real derivation and the binary exists for login shells.
  environment.systemPackages = with pkgs; [
    zsh
  ];

  # Enable NixOS's zsh program integration (optional but common).
  programs.zsh = {
    enable = true;
    # You can add other global zsh options here if needed.
  };

  # Provide a safe system-wide /etc/zshrc that demonstrates:
  # - using the Nix-resolved package path `${pkgs.zsh}` for SHELL
  # - using `$HOME` for the runtime user's home directory
  environment.etc."zshrc".text = ''
    # System-wide zshrc managed by Nix
    export SHELL=${pkgs.zsh}/bin/zsh

    # Load distribution/system zshenv if present
    if [ -f /etc/zsh/zshenv ]; then
      . /etc/zsh/zshenv
    fi

    # Initialize completion if available (safe/optional)
    if command -v compinit >/dev/null 2>&1; then
      autoload -Uz compinit && compinit || true
    fi

    # Source the user's ~/.zshrc if it exists. Use $HOME (runtime).
    if [ -n "$HOME" ] && [ -f "$HOME/.zshrc" ]; then
      . "$HOME/.zshrc"
    fi
  '';

  # Basic networking / time / SSH snippets to copy and adapt.
  networking.hostName = "<hostname>";
  # Enable NetworkManager if you prefer it for desktop/laptop use.
  networking.networkmanager.enable = true;

  # Time zone example; change to your local zone.
  time.timeZone = "America/New_York";

  # Enable OpenSSH server (adjust options as needed).
  services.openssh.enable = true;

  # Add any machine-specific options below.
  # For example:
  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  # nix.settings.trustedUsers = [ "<username>" ];
}
