{
  pkgs,
  inputs,
  ...
}: let
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  pinnedDevenv = inputs.devenv.packages.${pkgs.stdenv.hostPlatform.system}.devenv;
  homelabMachines = [
    "zero"
    "drlight"
    "type-nas"
    "type-server"
    "type-server-arm"
  ];
  personalMachines = [
    "bootstrap"
    "type-desktop"
    "installer-iso"
    "wweaver"
    "darwin-server"
    "MegamanX"
  ];
  profileChecks = assert builtins.all (name: (builtins.getAttr name catalog).secretProfile == "Homelab") homelabMachines;
  assert builtins.all (name: (builtins.getAttr name catalog).secretProfile == "Personal") personalMachines; true;
in {
  machineOps = assert profileChecks;
    pkgs.runCommand "machine-ops-safety-tests" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.jq];
    } ''
      MACHINE_OPS_SCRIPT=${../scripts/machine-ops.sh} bash ${./test-machine-ops.sh}
      touch $out
    '';

  secretspecEmptyProfiles =
    pkgs.runCommand "secretspec-empty-profile-safety-tests" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils];
    } ''
      SECRETSPEC_BIN=${pinnedDevenv}/bin/secretspec \
      SECRETSPEC_MANIFEST=${../secretspec.toml} \
      COREUTILS_BIN=${pkgs.coreutils}/bin \
        ${pkgs.bash}/bin/bash ${./test-secretspec-empty-profiles.sh}
      touch $out
    '';
}
