let
  sshPublicKey = import ../../library/ssh-public-key.nix;
in {
  # Initial monkey SSH access
  users.users.monkey.openssh.authorizedKeys.keys = [sshPublicKey];
}
