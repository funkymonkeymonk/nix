{darwinMachine, ...}: {
  "Lydia" = darwinMachine {
    secretProfile = "Opnix";
    system = "aarch64-darwin";
    hostname = "Lydia";
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
