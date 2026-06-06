{
  description = "Configuration library — reusable modules, archetypes, and system builders";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
    superpowers.url = "github:obra/superpowers";
    superpowers.flake = false;
    opnix.url = "github:brizzbuzz/opnix";
    opnix.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {nixpkgs, ...}: let
    inherit (nixpkgs) lib;
  in {
    lib = {
      inherit (import ./lib/mk-system.nix {inherit lib;}) mkDarwinSystem mkNixosSystem;
    };

    nixosModules.default = import ./flake-module.nix;

    flakeModules.default = import ./flake-module.nix;
  };
}
