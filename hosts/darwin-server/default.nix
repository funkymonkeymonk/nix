# darwin-server — headless macOS server for VM hosting
# Machine-specific overrides on top of headless-server-darwin archetype.
{
  mkUser,
  inputs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "monkey";

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      skills.superpowersPath = inputs.superpowers;
      opencode.enable = true;
    };
}
