{inputs, ...}: let
  devenvOverlay = import ../overlays/devenv.nix {inherit inputs;};
in {
  flake.nixosModules.library = {
    imports = [
      (import ../modules)
    ];
    nixpkgs.overlays = [devenvOverlay];
  };

  flake.darwinModules.library = {
    imports = [
      (import ../modules)
    ];
    nixpkgs.overlays = [devenvOverlay];
  };

  _module.args.libraryLib = import ./lib/mk-system.nix {lib = inputs.nixpkgs.lib;};
  _module.args.mkUser = import ./lib/mk-user.nix;
}
