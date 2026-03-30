# Ghostty terminfo support for SSH servers
# Ensures Ghostty's terminal definition is available on remote hosts
{
  pkgs,
  lib,
  ...
}: let
  # Ghostty is only available on Darwin platforms
  ghosttyAvailable = builtins.elem pkgs.stdenv.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"];
in {
  # Install ghostty terminfo into the system database
  # This allows Ghostty users to SSH into this host without terminfo errors
  environment.etc."terminfo/x/xterm-ghostty" = lib.mkIf ghosttyAvailable {
    source = "${pkgs.ghostty}/share/terminfo/x/xterm-ghostty";
  };

  # Ensure /etc/terminfo is in the terminfo search path (only on systems with ghostty)
  environment.sessionVariables = lib.mkIf ghosttyAvailable {
    TERMINFO_DIRS = "/etc/terminfo:/run/current-system/sw/share/terminfo";
  };
}
