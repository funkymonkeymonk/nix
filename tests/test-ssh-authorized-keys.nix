{
  pkgs,
  self,
  ...
}: let
  expectedPublicKey =
    builtins.replaceStrings ["\n" "\r"] ["" ""]
    (builtins.readFile ../keys/monkey-ssh.pub);
  publicKeyFiles =
    builtins.filter
    (name: builtins.match ".*\\.pub" name != null)
    (builtins.attrNames (builtins.readDir ../keys));
  clientKeyFiles = {
    zero = ../keys/nix-remote-builder-megamanx.pub;
    drlight = ../keys/nix-builder-client-drlight.pub;
    type-nas = ../keys/nix-builder-client-type-nas.pub;
    type-server = ../keys/nix-builder-client-type-server.pub;
    type-server-arm = ../keys/nix-builder-client-type-server-arm.pub;
    type-desktop = ../keys/nix-builder-client-type-desktop.pub;
    Lydia = ../keys/nix-builder-client-lydia.pub;
    MegamanX = ../keys/nix-builder-client-megamanx.pub;
    wweaver = ../keys/nix-builder-client-wweaver.pub;
  };
  clientNames = ["zero" "drlight" "type-nas" "type-server" "type-server-arm" "type-desktop" "Lydia" "MegamanX" "wweaver"];
  clientKey = name: let
    path = clientKeyFiles.${name};
  in
    if builtins.pathExists path
    then builtins.replaceStrings ["\n" "\r"] ["" ""] (builtins.readFile path)
    else "";
  builderKeysFor = builderName: map clientKey (builtins.filter (name: name != builderName) clientNames);
  expectedPublicKeyFiles = [
    "monkey-ssh.pub"
    "nix-builder-client-drlight.pub"
    "nix-builder-client-lydia.pub"
    "nix-builder-client-megamanx.pub"
    "nix-builder-client-type-desktop.pub"
    "nix-builder-client-type-nas.pub"
    "nix-builder-client-type-server-arm.pub"
    "nix-builder-client-type-server.pub"
    "nix-builder-client-wweaver.pub"
    "nix-remote-builder-megamanx.pub"
  ];
  installerScript = builtins.readFile ../scripts/nixos-install.sh;
  installerUsesCanonicalKey =
    pkgs.lib.hasInfix "monkey-ssh.pub" installerScript
    && !(pkgs.lib.hasInfix "username@hostname.pub" installerScript)
    && !(pkgs.lib.hasInfix "find \"$KEYS_DIR\" -name \"*.pub\"" installerScript)
    && !(pkgs.lib.hasInfix "for keyfile in \"$KEYS_DIR\"/*.pub" installerScript);
  installerLeavesGuestWithoutKeys = pkgs.lib.hasInfix ''
    users.users.guest = {
      isNormalUser = true;
      description = "Guest User";
      extraGroups = [ "networkmanager" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [];
    };''
  installerScript;
  hosts = [
    {
      name = "bootstrap";
      accounts = ["bootstrap" "root"];
    }
    {
      name = "drlight";
      accounts = ["monkey" "root"];
    }
    {
      name = "installer-iso";
      accounts = ["root"];
    }
    {
      name = "type-desktop";
      accounts = ["root"];
    }
    {
      name = "type-nas";
      accounts = ["monkey"];
    }
    {
      name = "type-server";
      accounts = ["monkey"];
    }
    {
      name = "type-server-arm";
      accounts = ["monkey"];
    }
    {
      name = "zero";
      accounts = ["root" "nixbuilder"];
      expectedKeysByAccount.nixbuilder = builderKeysFor "zero";
    }
  ];
  darwinHosts = [
    {
      name = "MegamanX";
      accounts = ["monkey" "nixbuilder"];
      expectedKeysByAccount = {
        monkey = [expectedPublicKey];
        nixbuilder = builderKeysFor "MegamanX";
      };
    }
    {
      name = "Lydia";
      accounts = ["monkey"];
      expectedKeysByAccount = {
        monkey = [expectedPublicKey];
      };
    }
    {
      name = "wweaver";
      accounts = ["wweaver"];
    }
  ];
  checkHost = configurations: host: let
    config = configurations.${host.name}.config;
    users = config.users.users;
    expectedKeysForAccount = account: builtins.sort builtins.lessThan ((host.expectedKeysByAccount or {}).${account} or [expectedPublicKey]);
    userKeys = account: (users.${account} or {}).openssh.authorizedKeys.keys or [];
    expectedHostKeys = builtins.concatLists (map expectedKeysForAccount host.accounts);
    actualAccountKeys = map (account: builtins.sort builtins.lessThan (userKeys account)) host.accounts;
    allConfiguredKeys = builtins.concatLists (map
      (user: user.openssh.authorizedKeys.keys or [])
      (builtins.attrValues users));
    actualKeyAccounts = builtins.sort builtins.lessThan (builtins.attrNames (pkgs.lib.filterAttrs
      (_: user: (user.openssh.authorizedKeys.keys or []) != [])
      users));
    expectedKeyAccounts = builtins.sort builtins.lessThan host.accounts;
    accountKeysMatch = actualAccountKeys == map expectedKeysForAccount host.accounts;
    keyScopesMatch = actualKeyAccounts == expectedKeyAccounts;
    noOtherKeys = builtins.all (key: builtins.elem key expectedHostKeys) allConfiguredKeys;
  in {
    inherit (host) name;
    passed = accountKeysMatch && keyScopesMatch && noOtherKeys;
  };
  checks =
    map (checkHost self.nixosConfigurations) hosts
    ++ map (checkHost self.darwinConfigurations) darwinHosts;
in
  pkgs.runCommand "test-ssh-authorized-keys" {} ''
    echo "=== Checking the managed SSH key on every system host ==="
    ${builtins.concatStringsSep "\n" (map (
        check:
          if check.passed
          then ''echo "${check.name}: approved SSH public keys are authorized only on their intended accounts: OK"''
          else ''echo "FAIL: ${check.name} must authorize approved SSH public keys only on their intended accounts"; exit 1''
      )
      checks)}
    ${
      if publicKeyFiles == expectedPublicKeyFiles && installerUsesCanonicalKey && installerLeavesGuestWithoutKeys && builtins.all (name: clientKey name != "") clientNames
      then ''echo "The key registry is complete and the legacy installer scopes login access: OK"''
      else ''echo "FAIL: public keys must be explicitly registered and the installer must not grant builder keys to login accounts"; exit 1''
    }
    touch $out
  ''
