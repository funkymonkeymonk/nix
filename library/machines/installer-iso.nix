{inputs, ...}: {
  flake.nixosConfigurations.installer-iso = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {inherit inputs;};
    modules = [
      ../../targets/installer-iso/default.nix
    ];
  };
}
