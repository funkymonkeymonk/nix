let
  sshPublicKey = import ../../library/ssh-public-key.nix;
in {
  users.users.root.openssh.authorizedKeys.keys = [sshPublicKey];
}
