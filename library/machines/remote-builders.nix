{config, lib, ...}: let
  registry = import ../ssh-key-registry.nix;
  machineName =
    if builtins.isString (config.networking.hostName or null)
    then config.networking.hostName
    else "";
  client = registry.clients.${machineName} or null;
  isDarwin = config.myConfig.isDarwin or false;
  sshKeyPath = if isDarwin then "/var/run/nix-builder-client" else "/run/secrets/nix-builder-client";
  remoteBuilders = builtins.filter (builder: builder.name != machineName) (builtins.attrValues registry.builders);
  machineLine = builder:
    lib.concatStringsSep " " [
      "ssh-ng://nixbuilder@${builder.hostName}"
      builder.system
      sshKeyPath
      (toString builder.maxJobs)
      (toString builder.speedFactor)
      (lib.concatStringsSep "," builder.supportedFeatures)
      "-"
      builder.publicHostKey
    ];
  darwinNixConfig = [
    "builders = @/etc/nix/machines"
    "builders-use-substitutes = true"
  ]
  ++ lib.optional (builtins.hasAttr machineName registry.builders) "trusted-users = root monkey nixbuilder";
in {
  config = lib.mkIf (client != null) (lib.mkMerge [
    {
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
    }
    (if isDarwin
    then {
      environment.etc."nix/machines".text = lib.concatStringsSep "\n" (map machineLine remoteBuilders) + "\n";
      environment.etc."nix/nix.custom.conf".text = lib.concatStringsSep "\n" darwinNixConfig + "\n";
    }
    else {
      nix = {
        distributedBuilds = true;
        settings.builders-use-substitutes = true;
        buildMachines = map (builder: {
          hostName = builder.hostName;
          inherit (builder) system maxJobs speedFactor supportedFeatures publicHostKey;
          protocol = "ssh-ng";
          sshUser = "nixbuilder";
          sshKey = sshKeyPath;
        }) remoteBuilders;
      };
    })
  ]);
}
