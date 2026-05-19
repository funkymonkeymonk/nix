{
  description = "Profile schema — shared contract between library and profile flakes";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs}: let
    inherit (nixpkgs) lib;
  in {
    lib = {
      inherit (import ./modules/validator.nix {inherit lib;}) mkProfile;
    };

    nixosModules.profile = import ./modules/profile.nix;

    flakeModules.default = import ./flake-module.nix;
  };
}
