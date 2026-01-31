{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.onepassword;
  isDarwin = builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"];
  isLinux = builtins.elem config.nixpkgs.hostPlatform.system ["x86_64-linux" "aarch64-linux"];
in {
  config = mkIf cfg.enable {
    # Install 1Password CLI via Nix packages
    programs._1password = {
      enable = true;
      # Use unstable for latest versions
      package = pkgs.unstable._1password-cli;
    };

    # For Linux GUI, it should be installed via system packages or homebrew
    # The GUI package requires polkit configuration that's more complex
    # We're focusing on CLI access which is what's needed for git signing
  };
}
