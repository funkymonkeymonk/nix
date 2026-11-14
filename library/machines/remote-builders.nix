{
  config,
  lib,
  ...
}: let
  registry = import ../ssh-key-registry.nix;
  machineName =
    if builtins.isString (config.networking.hostName or null)
    then config.networking.hostName
    else "";
  client = registry.clients.${machineName} or null;
  sshKeyPath =
    if (config.myConfig.isDarwin or false)
    then "/var/run/nix-builder-client"
    else "/run/secrets/nix-builder-client";
  remoteBuilders = builtins.filter (builder: builder.name != machineName) (builtins.attrValues registry.builders);
in {
  config = lib.mkIf (client != null) {
    myConfig.onepassword = {
      tokenFile = lib.mkDefault "/etc/opnix/token";
      secrets.nixBuilderClientKey = {
        reference = client.secretReference;
        path = sshKeyPath;
        mode = "0400";
        owner = "root";
        group = "root";
      };
    };

    services.onepassword-secrets.enable = true;

    nix = {
      distributedBuilds = true;
      settings.builders-use-substitutes = true;
      buildMachines =
        map (builder: {
          hostName = builder.hostName;
          inherit (builder) system maxJobs speedFactor supportedFeatures publicHostKey;
          protocol = "ssh-ng";
          sshUser = "nixbuilder";
          sshKey = sshKeyPath;
        })
        remoteBuilders;
    };
  };
}
