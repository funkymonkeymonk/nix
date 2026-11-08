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
  nixBuilderPublicKeyPath = ../keys/nix-remote-builder-megamanx.pub;
  nixBuilderPublicKey =
    if builtins.pathExists nixBuilderPublicKeyPath
    then builtins.replaceStrings ["\n" "\r"] ["" ""] (builtins.readFile nixBuilderPublicKeyPath)
    else "";
  installerScript = builtins.readFile ../scripts/nixos-install.sh;
  installerUsesCanonicalKey =
    pkgs.lib.hasInfix "keys/monkey-ssh.pub" installerScript
    && !(pkgs.lib.hasInfix "username@hostname.pub" installerScript);
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
      accounts = ["root"];
    }
  ];
  darwinHosts = [
    {
      name = "MegamanX";
      accounts = ["monkey"];
      extraKeysByAccount.monkey = [nixBuilderPublicKey];
    }
    {
      name = "darwin-server";
      accounts = ["monkey"];
    }
    {
      name = "wweaver";
      accounts = ["wweaver"];
    }
  ];
  checkHost = configurations: host: let
    config = configurations.${host.name}.config;
    users = config.users.users;
    extraKeysForAccount = account: (host.extraKeysByAccount or {}).${account} or [];
    expectedKeysForAccount = account: builtins.sort builtins.lessThan ([expectedPublicKey] ++ extraKeysForAccount account);
    expectedHostKeys = builtins.concatLists (map expectedKeysForAccount host.accounts);
    actualAccountKeys =
      map
      (account: builtins.sort builtins.lessThan (users.${account}.openssh.authorizedKeys.keys or []))
      host.accounts;
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
          then ''echo "${check.name}: only the approved SSH public key is authorized: OK"''
          else ''echo "FAIL: ${check.name} must authorize only the approved SSH public key on its existing access account"; exit 1''
      )
      checks)}
    ${
      if publicKeyFiles == ["monkey-ssh.pub" "nix-remote-builder-megamanx.pub"] && installerUsesCanonicalKey && nixBuilderPublicKey != ""
      then ''echo "Installer and key directory contain the approved and remote-builder public keys: OK"''
      else ''echo "FAIL: installer and key directory must use only the canonical SSH public key"; exit 1''
    }
    touch $out
  ''
