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
  remoteBuilders = builtins.filter (builder: builder.name != machineName) (builtins.attrValues registry.builders);
  machineLine = keyPath: builder:
    lib.concatStringsSep " " [
      "ssh-ng://nixbuilder@${builder.hostName}"
      builder.system
      keyPath
      (toString builder.maxJobs)
      (toString builder.speedFactor)
      (lib.concatStringsSep "," builder.supportedFeatures)
      "-"
      builder.publicHostKey
    ];
  darwinNixConfig =
    [
      "builders = @/etc/nix/machines"
      "builders-use-substitutes = true"
    ]
    ++ lib.optional (builtins.hasAttr machineName registry.builders) "trusted-users = root monkey nixbuilder";
in {
  config = lib.mkMerge [
    (lib.mkIf (client != null) {
      myConfig.onepassword = {
        tokenFile = lib.mkDefault "/etc/opnix/token";
        secrets.nixBuilderClientKey = {
          reference = client.secretReference;
          mode = "0400";
          owner = "root";
          group = "root";
        };
      };

      services.onepassword-secrets.enable = true;
    })
    (lib.mkIf (client != null && (config.myConfig.isDarwin or false)) {
      myConfig.onepassword.secrets.nixBuilderClientKey.path = "/var/run/nix-builder-client";

      environment.etc."nix/machines".text = lib.concatStringsSep "\n" (map (machineLine "/var/run/nix-builder-client") remoteBuilders) + "\n";
      environment.etc."nix/nix.custom.conf".text = lib.concatStringsSep "\n" darwinNixConfig + "\n";
    })
    (lib.mkIf (client != null && !(config.myConfig.isDarwin or false)) {
      myConfig.onepassword.secrets.nixBuilderClientKey.path = "/run/secrets/nix-builder-client";

      nix = {
        distributedBuilds = true;
        settings.builders-use-substitutes = true;
        buildMachines =
          map (builder: {
            hostName = builder.hostName;
            inherit (builder) system maxJobs speedFactor supportedFeatures publicHostKey;
            protocol = "ssh-ng";
            sshUser = "nixbuilder";
            sshKey = "/run/secrets/nix-builder-client";
          })
          remoteBuilders;
      };
    })
  ];
}
