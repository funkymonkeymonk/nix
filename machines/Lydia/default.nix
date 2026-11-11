{lib, ...}: {
  # Target system: aarch64-darwin
  imports = [
    ../../library/archetypes/workstation-darwin.nix
  ];

  system.stateVersion = 4;
  system.primaryUser = "monkey";
  myConfig.users = lib.mkDefault [
    {
      name = "monkey";
      fullName = "monkey";
      email = "me@willweaver.dev";
    }
  ];
  myConfig.roles."developer".enable = true;
  myConfig.roles."desktop".enable = true;
  myConfig.roles."workstation".enable = true;
  myConfig.roles."agent-skills".enable = true;
  myConfig.roles."pi".enable = true;
}
