{...}: let
  # This variable contains only the public half of a disposable keypair. It is
  # intentionally embedded in this throwaway VM's authorized_keys; the private
  # half never enters Nix evaluation or the store.
  publicKey = builtins.getEnv "MACHINES_E2E_PUBLIC_KEY";
  portText = builtins.getEnv "MACHINES_E2E_SSH_PORT";
  deploymentSystemPath = builtins.getEnv "MACHINES_E2E_DEPLOYMENT_SYSTEM";
  validPortText = builtins.match "[1-9][0-9]{0,4}" portText != null;
  validDeploymentSystem = builtins.match "/nix/store/[a-z0-9]{32}-nixos-system-[^/]+" deploymentSystemPath != null;
  port =
    if validPortText
    then builtins.fromJSON portText
    else 0;
in
  if publicKey == ""
  then throw "MACHINES_E2E_PUBLIC_KEY must contain the disposable VM's public key"
  else if !validPortText || port > 65535
  then throw "MACHINES_E2E_SSH_PORT must contain an available TCP port"
  else if !validDeploymentSystem
  then throw "MACHINES_E2E_DEPLOYMENT_SYSTEM must contain a NixOS system output in the store"
  else {
    system.stateVersion = "25.05";
    virtualisation.additionalPaths = [(builtins.storePath deploymentSystemPath)];

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        PubkeyAuthentication = true;
      };
    };

    users.users.root.openssh.authorizedKeys.keys = [publicKey];
    networking.firewall.allowedTCPPorts = [22];

    virtualisation = {
      # Boot a regular VM disk with a local store. A shared host-store mount
      # would be removed by the normal deployed NixOS role during activation.
      # Seed the synthetic target's full closure into the initial image so the
      # guest can accept the deployment without requiring a shared Nix store.
      useBootLoader = true;
      mountHostNixStore = false;
      # The Machines apply step copies the complete requested NixOS closure to
      # the guest store in addition to the booted base system.
      diskSize = 32768;
      memorySize = 2048;
      cores = 2;
      restrictNetwork = true;
      writableStoreUseTmpfs = false;
      forwardPorts = [
        {
          from = "host";
          host.address = "127.0.0.1";
          host.port = port;
          guest.port = 22;
        }
      ];
    };
  }
