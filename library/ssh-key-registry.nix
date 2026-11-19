let
  readPublicKey = path:
    builtins.replaceStrings ["\n" "\r"] ["" ""] (builtins.readFile path);

  client = publicKeyPath: secretReference: {
    publicKey = readPublicKey publicKeyPath;
    inherit secretReference;
  };

  clients = {
    zero = client ../keys/nix-remote-builder-megamanx.pub "Nix Remote Builder Zero to MegamanX/private key";
    drlight = client ../keys/nix-builder-client-drlight.pub "Nix Builder Client drlight/private key";
    type-nas = client ../keys/nix-builder-client-type-nas.pub "Nix Builder Client type-nas/private key";
    type-server = client ../keys/nix-builder-client-type-server.pub "Nix Builder Client type-server/private key";
    type-server-arm = client ../keys/nix-builder-client-type-server-arm.pub "Nix Builder Client type-server-arm/private key";
    type-desktop = client ../keys/nix-builder-client-type-desktop.pub "Nix Builder Client type-desktop/private key";
    Lydia = client ../keys/nix-builder-client-lydia.pub "Nix Builder Client Lydia/private key";
    MegamanX = client ../keys/nix-builder-client-megamanx.pub "Nix Builder Client MegamanX/private key";
    wweaver = client ../keys/nix-builder-client-wweaver.pub "Nix Builder Client wweaver/private key";
  };

  builders = {
    zero = {
      name = "zero";
      hostName = "zero";
      system = "x86_64-linux";
      hostPublicKeyFile = ../keys/hosts/zero.pub;
      # SHA256:ecznS63w+1xnEi26/N/n2l9x6jVcUHOWe1sQq3rnEb4 (verified on Zero)
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUhHdDUxZnFadXQyZzVxNllDaWdzOGk1WUVsQXl6aExYMnBjVm9LZ3VObzYgcm9vdEBuaXhvcwo=";
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = ["big-parallel"];
    };

    MegamanX = {
      name = "MegamanX";
      hostName = "megamanx";
      system = "aarch64-darwin";
      hostPublicKeyFile = ../keys/hosts/megamanx.pub;
      # SHA256:oKWYFmofAPEGxvdlXSCtDne8Ltj4y0MoNtPAXVbx8io (verified in known_hosts)
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU9Hd2lqRkxveHN2UVRhcDJScWVrWmdnS3krMlJzVUZDVnRrT28wSWtUN3QK";
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = ["big-parallel"];
    };
  };
in {
  inherit builders clients;
  clientNames = builtins.attrNames clients;
}
