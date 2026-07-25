# Workstation Darwin archetype — personal developer workstation
{
  inputs,
  lib,
  ...
}: {
  imports = [
    ../../modules/roles/homebrew.nix
  ];

  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;

    roles = {
      developer.enable = true;
      desktop.enable = true;
      workstation.enable = true;
      pi.enable = true;
      homebrew.enable = true;
    };

    # pi-plugins flake input, provided here (not in modules/roles/pi.nix) so
    # the role module itself doesn't need `inputs` directly — mirrors
    # skills.superpowersPath above. Override per-machine with a direct
    # assignment, e.g. for a local pi-plugins checkout during development.
    pi.pluginsSource = lib.mkDefault (inputs.pi-plugins.outPath or null);
  };
}
