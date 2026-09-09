{inputs, ...}: {
  flake.nixosConfigurations.bootstrap = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../../modules/common/core.nix
      ../../targets/bootstrap
      ../../modules/common/options.nix
    ];
  };
}
