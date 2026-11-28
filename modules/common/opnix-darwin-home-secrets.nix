{
  config,
  lib,
  ...
}: let
  hmLib = import ../home-manager/lib.nix {inherit lib;};
  mkSecretsForUser = user: let
    username = user.name;
    isDarwin = true;
    cfg = config.myConfig;
    setOwner = secrets: lib.mapAttrs (_name: secret: secret // {owner = username;}) secrets;
    piSecrets =
      setOwner (hmLib.mkOpnixSecrets "pi" cfg.onepassword.defaultVault isDarwin (
        lib.mapAttrs (name: model: {
          inherit (model) onePasswordItem;
          secretPath = ".pi/agent/secrets/${name}-apikey";
        })
        (lib.filterAttrs (_name: model: model.onePasswordItem != "") cfg.pi.models)
      ))
      // setOwner (hmLib.mkOpnixSecrets "pi" cfg.onepassword.defaultVault isDarwin (
        lib.optionalAttrs (cfg.pi.opencodeGoOnePasswordItem != "") {
          opencode-go = {
            onePasswordItem = cfg.pi.opencodeGoOnePasswordItem;
            secretPath = ".pi/agent/secrets/opencode-go-apikey";
          };
        }
      ))
      // setOwner (hmLib.mkOpnixSecrets "pi" cfg.onepassword.defaultVault isDarwin (
        lib.optionalAttrs (cfg.pi.jevOnePasswordItem != "") {
          jev = {
            onePasswordItem = cfg.pi.jevOnePasswordItem;
            secretPath = ".pi/agent/secrets/typesafe_api_key";
          };
        }
      ));
    opencodeProviders =
      lib.filterAttrs (
        _name: provider: provider.onePasswordItem != ""
      )
      cfg.opencode.providers;
    opencodeBaseUrls =
      lib.filterAttrs (
        _name: provider: provider.baseURLOpnixItem != ""
      )
      cfg.opencode.providers;
    opencodeSecrets =
      setOwner (hmLib.mkOpnixSecrets "opencode" cfg.onepassword.defaultVault isDarwin (
        lib.mapAttrs (_name: provider: {
          inherit (provider) onePasswordItem;
          secretPath = ".config/opencode/secrets/${_name}-apikey";
        })
        opencodeProviders
      ))
      // setOwner (hmLib.mkOpnixSecretsGeneric "opencode" cfg.onepassword.defaultVault isDarwin (
        lib.mapAttrs (_name: provider: {
          reference = provider.baseURLOpnixItem;
          path = ".config/opencode/secrets/${_name}-baseurl";
        })
        opencodeBaseUrls
      ));
    claudeServers =
      lib.filterAttrs (
        _name: server: server.onePasswordItem != ""
      )
      cfg.claude-code.mcpServers;
    claudeSecrets = setOwner (hmLib.mkOpnixSecrets "claudeCode" cfg.onepassword.defaultVault isDarwin (
      lib.mapAttrs (_name: server: {
        inherit (server) onePasswordItem;
        secretPath = ".config/claude-code/secrets/${_name}-apikey";
      })
      claudeServers
    ));
  in
    (
      if cfg.pi.enable
      then piSecrets
      else {}
    )
    // (
      if cfg.opencode.enable
      then opencodeSecrets
      else {}
    )
    // (
      if cfg.claude-code.enable
      then claudeSecrets
      else {}
    );
  userSecrets =
    lib.foldl' (
      accumulated: user: let
        secrets = mkSecretsForUser user;
      in
        accumulated
        // lib.mapAttrs' (name: secret:
          lib.nameValuePair "${user.name}${lib.toUpper (lib.substring 0 1 name)}${lib.substring 1 (-1) name}" (
            secret // {path = "/Users/${user.name}/${secret.path}";}
          ))
        secrets
    ) {}
    config.myConfig.users;
  userSecretsFor = username:
    lib.filterAttrs (name: _: lib.hasPrefix username name) userSecrets;
  usersWithSecrets = lib.filter (username: userSecretsFor username != {}) (map (user: user.name) config.myConfig.users);
in {
  config = lib.mkIf (config.myConfig.isDarwin && config.myConfig.onepassword.enable) {
    services.onepassword-secrets = {
      enable = lib.mkDefault (userSecrets != {});
      users = usersWithSecrets;
      outputDir = "/usr/local/var/opnix/secrets";
      secrets = userSecrets;
    };

    home-manager.sharedModules = [
      ({lib, ...}: {
        config.programs.onepassword-secrets.enable = lib.mkForce false;
      })
    ];
  };
}
