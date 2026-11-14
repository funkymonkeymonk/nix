{
  pkgs,
  self ? null,
  inputs ? {},
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
      publicKeyFile = ../keys/hosts/zero.pub;
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = ["big-parallel"];
    }
    {
      name = "MegamanX";
      hostName = "megamanx";
      system = "aarch64-darwin";
      publicKeyFile = ../keys/hosts/megamanx.pub;
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = ["big-parallel"];
    }
  ];
  configurations =
    if self == null
    then {}
    else self.nixosConfigurations // self.darwinConfigurations;
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  configFor = name: configurations.${name}.config;
  opnixTokenInstallValid = name: let
    installSecrets = (catalog.${name}.install or {}).secrets or {};
    token = installSecrets."/etc/opnix/token" or {};
  in
    (token.secret or null)
    == "OPNIX_SERVICE_ACCOUNT_TOKEN"
    && (token.owner or null) == "0:0"
    && (token.mode or null) == "0600";
  expectedBuildersFor = client: builtins.filter (builder: builder.name != client) builders;
  machineMatches = machine: builder: machine.hostName == builder.hostName && machine.system == builder.system;
  builderLine = keyPath: builder:
    lib.concatStringsSep " " [
      "ssh-ng://nixbuilder@${builder.hostName}"
      builder.system
      keyPath
      (toString builder.maxJobs)
      (toString builder.speedFactor)
      (lib.concatStringsSep "," builder.supportedFeatures)
      "-"
      (hostPinFor builder.name)
    ];
  pinForBuilder = builder: let
    clients = builtins.filter (client: client != builder.name) clientNames;
    clientConfig = configFor (builtins.head clients);
    matches = builtins.filter (machine: machine.hostName == builder.hostName) (clientConfig.nix.buildMachines or []);
  in {
    inherit (builder) name publicKeyFile;
    value =
      if matches == []
      then ""
      else ((builtins.head matches).publicHostKey or "");
  };
  builderPins = map pinForBuilder builders;
  hostPinFor = name: (lib.findFirst (pin: pin.name == name) {value = "";} builderPins).value;
  clientTopologyValid = client: let
    config = configFor client;
    expected = expectedBuildersFor client;
    isDarwin = config.myConfig.isDarwin or false;
    actualNixos = config.nix.buildMachines or [];
    expectedDarwinLines = map (builder: builderLine "/var/run/nix-builder-client" builder) expected;
    darwinMachinesFile = config.environment.etc."nix/machines".text or "";
    darwinCustomConf = config.environment.etc."nix/nix.custom.conf".text or "";
    actualDarwinLines = lib.filter (line: line != "") (lib.splitString "\n" darwinMachinesFile);
    exactNixosPeerSet =
      builtins.length actualNixos
      == builtins.length expected
      && builtins.all (builder: builtins.any (machine: machineMatches machine builder) actualNixos) expected
      && builtins.all (machine: builtins.any (builder: machineMatches machine builder) expected) actualNixos;
    exactDarwinPeerSet =
      builtins.length actualDarwinLines
      == builtins.length expectedDarwinLines
      && builtins.all (line: builtins.elem line actualDarwinLines) expectedDarwinLines;
    nixosEntriesSecure = builtins.all (machine:
      machine.protocol
      == "ssh-ng"
      && machine.sshUser == "nixbuilder"
      && builtins.isString (machine.sshKey or null)
      && !(lib.hasPrefix "/nix/store/" (machine.sshKey or ""))
      && builtins.isString (machine.publicHostKey or null)
      && (machine.publicHostKey or "") != "")
    actualNixos;
  in
    if isDarwin
    then
      !(config.nix.enable)
      && exactDarwinPeerSet
      && lib.hasInfix "builders = @/etc/nix/machines" darwinCustomConf
      && lib.hasInfix "builders-use-substitutes = true" darwinCustomConf
    else
      config.nix.distributedBuilds
      && (config.nix.settings.builders-use-substitutes or false)
      && exactNixosPeerSet
      && nixosEntriesSecure;
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
    isDarwin = config.myConfig.isDarwin or false;
    buildMachines =
      if isDarwin
      then []
      else (config.nix.buildMachines or []);
    darwinMachinesFile = config.environment.etc."nix/machines".text or "";
  in
    (secret.reference or null)
    == expectedSecretReference client
    && (secret.path or null) == expectedPath
    && (secret.owner or null) == "root"
    && (secret.group or null) == "root"
    && (secret.mode or null) == "0400"
    && (
      if isDarwin
      then lib.hasInfix expectedPath darwinMachinesFile
      else builtins.all (machine: machine.sshKey == expectedPath) buildMachines
    )
    && ((config.services.onepassword-secrets or {}).enable or false);
  expectedAuthorizedKeys = builderName:
    map publicKeyFor (builtins.filter (client: client != builderName) clientNames);
  authorizedKeysFor = name:
    ((configFor name).users.users.nixbuilder or {}).openssh.authorizedKeys.keys or [];
  restrictedNixbuilderSsh = name: let
    config = configFor name;
    sshConfig = config.services.openssh.extraConfig or "";
    trustedUsersConfigured =
      if (config.myConfig.isDarwin or false)
      then lib.hasInfix "trusted-users = root monkey nixbuilder" (config.environment.etc."nix/nix.custom.conf".text or "")
      else builtins.elem "nixbuilder" (config.nix.settings.trusted-users or []);
  in
    trustedUsersConfigured
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
      name = "every client has a SecretSpec Opnix token install with root-only permissions";
      passed = builtins.all opnixTokenInstallValid clientNames;
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
        && !(lib.hasInfix "nixbuilder" ((configFor "Lydia").environment.etc."nix/nix.custom.conf".text or ""));
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
      pkgs.runCommand "test-ssh-builders" {
        nativeBuildInputs = [pkgs.coreutils pkgs.openssh];
      } ''
        failures=0
        echo "=== Testing the reciprocal SSH builder registry ==="
        ${builtins.concatStringsSep "\n" (map (pin: ''
            tmp=$(mktemp)
            if printf '%s' '${pin.value}' | base64 -d > "$tmp"; then
              pin_fingerprint=$(ssh-keygen -lf "$tmp" | awk '{print $2}')
              source_fingerprint=$(ssh-keygen -lf ${lib.escapeShellArg (toString pin.publicKeyFile)} | awk '{print $2}')
            else
              pin_fingerprint=invalid
              source_fingerprint=unavailable
            fi
            if [ "$pin_fingerprint" = "$source_fingerprint" ] && [ "$pin_fingerprint" != invalid ]; then
              echo "  ${pin.name} host-key pin fingerprint matches its public key: OK"
            else
              echo "  FAIL: ${pin.name} host-key pin fingerprint $pin_fingerprint does not match source $source_fingerprint"
              failures=1
            fi
            rm -f "$tmp"
          '')
          builderPins)}
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
