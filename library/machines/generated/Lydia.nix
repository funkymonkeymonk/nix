{darwinMachine, ...}: {
  "Lydia" = darwinMachine {
    secretProfile = "Opnix";
    system = "aarch64-darwin";
    hostname = "Lydia";
    install = {
      secrets."/etc/opnix-token" = {
        secret = "OPNIX_SERVICE_ACCOUNT_TOKEN";
        owner = "0:0";
        mode = "0600";
      };
    };
    modules = [../../../machines/Lydia];
    overrides = {
      users = [
        {
          name = "monkey";
          fullName = "monkey";
          email = "me@willweaver.dev";
        }
      ];
    };
  };
}
