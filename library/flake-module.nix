_: {
  flake.nixosModules.library = {
    imports = [
      (import ../modules)
    ];
  };
}
