# Ghostty terminfo support for SSH servers
# Ensures Ghostty's terminal definition is available on remote hosts
{pkgs, ...}: {
  # Install ghostty terminfo into the system database
  # This allows Ghostty users to SSH into this host without terminfo errors
  environment.etc."terminfo/x".source = pkgs.runCommand "ghostty-terminfo-x" {} ''
    mkdir -p $out
    ln -s ${pkgs.ghostty}/share/terminfo/x/xterm-ghostty $out/xterm-ghostty
  '';
}
