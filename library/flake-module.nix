{inputs, ...}: {
  flake.nixosModules.library = {
    imports = [
      (import ../modules)
    ];
  };

  _module.args.libraryLib = import ./lib/mk-system.nix {lib = inputs.nixpkgs.lib;};
  _module.args.mkUser = import ./lib/mk-user.nix;
}
