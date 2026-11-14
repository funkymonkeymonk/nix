{
  pkgs,
  self ? null,
  ...
}: let
  lib = pkgs.lib;
  clientNames = [
    "zero"
    "drlight"
    "type-nas"
    "type-server"
    "type-server-arm"
    "type-desktop"
    "Lydia"
    "MegamanX"
    "wweaver"
  ];
  clientKeyPaths = {
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
  publicKeyFor = name: let
    path = clientKeyPaths.${name};
  in
    if builtins.pathExists path
    then builtins.replaceStrings ["\n" "\r"] ["" ""] (builtins.readFile path)
    else "";
  clientPublicKeys = map publicKeyFor clientNames;
  clientKeyBlobs = map (key: lib.concatStringsSep " " (lib.take 2 (lib.splitString " " key))) clientPublicKeys;
  builders = [
    {
      name = "zero";
      hostName = "zero";
      system = "x86_64-linux";
    }
    {
      name = "MegamanX";
      hostName = "megamanx";
      system = "aarch64-darwin";
    }
  ];
  configurations =
    if self == null
    then {}
    else self.nixosConfigurations // self.darwinConfigurations;
  configFor = name: configurations.${name}.config;
  expectedBuildersFor = client: builtins.filter (builder: builder.name != client) builders;
  machineMatches = machine: builder: machine.hostName == builder.hostName && machine.system == builder.system;
  clientTopologyValid = client: let
    config = configFor client;
    actual = config.nix.buildMachines or [];
    expected = expectedBuildersFor client;
    exactPeerSet =
      builtins.length actual
      == builtins.length expected
      && builtins.all (builder: builtins.any (machine: machineMatches machine builder) actual) expected
      && builtins.all (machine: builtins.any (builder: machineMatches machine builder) expected) actual;
    allEntriesSecure = builtins.all (machine:
      machine.protocol
      == "ssh-ng"
      && machine.sshUser == "nixbuilder"
      && builtins.isString (machine.sshKey or null)
      && !(lib.hasPrefix "/nix/store/" (machine.sshKey or ""))
      && builtins.isString (machine.publicHostKey or null)
      && (machine.publicHostKey or "") != "")
    actual;
  in
    config.nix.distributedBuilds
    && (config.nix.settings.builders-use-substitutes or false)
    && exactPeerSet
    && allEntriesSecure;
  expectedSecretReference = name:
    if name == "zero"
    then "Nix Remote Builder Zero to MegamanX/private key"
    else "Nix Builder Client ${name}/private key";
  clientSecretValid = client: let
    config = configFor client;
    secret = config.myConfig.onepassword.secrets.nixBuilderClientKey or {};
    expectedPath =
      if (config.myConfig.isDarwin or false)
      then "/var/run/nix-builder-client"
      else "/run/secrets/nix-builder-client";
    buildMachines = config.nix.buildMachines or [];
  in
    (secret.reference or null)
    == expectedSecretReference client
    && (secret.path or null) == expectedPath
    && (secret.owner or null) == "root"
    && (secret.group or null) == "root"
    && (secret.mode or null) == "0400"
    && builtins.all (machine: machine.sshKey == expectedPath) buildMachines
    && ((config.services.onepassword-secrets or {}).enable or false);
  expectedAuthorizedKeys = builderName:
    map publicKeyFor (builtins.filter (client: client != builderName) clientNames);
  authorizedKeysFor = name:
    ((configFor name).users.users.nixbuilder or {}).openssh.authorizedKeys.keys or [];
  restrictedNixbuilderSsh = name: let
    config = configFor name;
    sshConfig = config.services.openssh.extraConfig or "";
  in
    builtins.elem "nixbuilder" (config.nix.settings.trusted-users or [])
    && lib.hasInfix "Match User nixbuilder" sshConfig
    && lib.hasInfix "AuthenticationMethods publickey" sshConfig
    && lib.hasInfix "PasswordAuthentication no" sshConfig
    && lib.hasInfix "KbdInteractiveAuthentication no" sshConfig
    && lib.hasInfix "AllowAgentForwarding no" sshConfig
    && lib.hasInfix "AllowTcpForwarding no" sshConfig
    && lib.hasInfix "PermitTTY no" sshConfig
    && lib.hasInfix "X11Forwarding no" sshConfig
    && lib.hasInfix "ForceCommand /nix/var/nix/profiles/default/bin/nix-daemon --stdio" sshConfig;
  builderAuthorizationValid = builderName:
    builtins.sort builtins.lessThan (authorizedKeysFor builderName)
    == builtins.sort builtins.lessThan (expectedAuthorizedKeys builderName);
  allClientKeysPresentAndUnique =
    builtins.all (key: key != "" && builtins.match "ssh-ed25519 [A-Za-z0-9+/]+={0,2}( .*)?" key != null) clientPublicKeys
    && builtins.length (lib.unique clientKeyBlobs) == builtins.length clientNames;
  testResults = [
    {
      name = "the exact nine long-lived systems have distinct Ed25519 client keys";
      passed = allClientKeysPresentAndUnique;
    }
    {
      name = "all clients use the compatible remote builder peers, pinned host keys, and local secret-file paths";
      passed = builtins.all clientTopologyValid clientNames && builtins.all clientSecretValid clientNames;
    }
    {
      name = "Zero authorizes every other client, not its own key";
      passed = builderAuthorizationValid "zero" && restrictedNixbuilderSsh "zero";
    }
    {
      name = "MegamanX authorizes every other client, not its own key";
      passed = builderAuthorizationValid "MegamanX" && restrictedNixbuilderSsh "MegamanX";
    }
    {
      name = "Lydia is a client only and does not expose a Nix builder account";
      passed =
        !(builtins.hasAttr "nixbuilder" (configFor "Lydia").users.users)
        && !(builtins.elem "nixbuilder" ((configFor "Lydia").nix.settings.trusted-users or []));
    }
  ];
in {
  sshBuilders =
    if self == null
    then
      pkgs.runCommand "test-ssh-builders-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else
      pkgs.runCommand "test-ssh-builders" {} ''
        failures=0
        echo "=== Testing the reciprocal SSH builder registry ==="
        ${builtins.concatStringsSep "\n" (map (check: ''
            if ${lib.boolToString check.passed}; then
              echo "  ${check.name}: OK"
            else
              echo "  FAIL: ${check.name}"
              failures=1
            fi
          '')
          testResults)}
        if [ "$failures" -ne 0 ]; then exit 1; fi
        touch $out
      '';
}
