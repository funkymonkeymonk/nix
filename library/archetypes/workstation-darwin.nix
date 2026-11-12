# Workstation Darwin archetype — developer workstation/desktop
{
  inputs,
  lib,
  ...
}: {
  imports = [
    ./base-darwin.nix
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

  myConfig = {
    roles = {
      developer.enable = true;
      desktop.enable = true;
      workstation.enable = true;
      pi.enable = true;
      homebrew.enable = true;
      entertainment.enable = true;
    };

    # pi-plugins flake input, provided here (not in modules/roles/pi.nix) so
    # the role module itself doesn't need `inputs` directly. Override per-machine
    # with a direct assignment for a local pi-plugins checkout during development.
    pi.pluginsSource = lib.mkDefault (inputs.pi-plugins.outPath or null);
  };

  time.timeZone = "America/New_York";
}
