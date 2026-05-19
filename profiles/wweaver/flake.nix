{
  description = "Will Weaver work profile";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    schema.url = "github:funkymonkeymonk/nix?dir=schema";
  };

  outputs = {schema, ...}: {
    myProfile = schema.lib.mkProfile (import ./profile.nix);
  };
}
