{
  inputs,
  libraryLib,
  ...
}:
import ./flake-configurations.nix {
  inherit inputs libraryLib;
  catalog = import ./catalog.nix {inherit inputs;};
}
