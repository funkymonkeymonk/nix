# Ghostty terminfo support for SSH servers
# Ensures Ghostty's terminal definition is available on remote hosts
{pkgs, ...}: {
  # Install ghostty terminfo into the system database
  # This allows Ghostty users to SSH into this host without terminfo errors
  environment.etc."terminfo/x/xterm-ghostty".source = "${pkgs.ghostty}/share/terminfo/x/xterm-ghostty";
}
