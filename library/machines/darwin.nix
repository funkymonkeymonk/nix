# Darwin machine targets.
#
# Keep these configurations together because flake-parts treats the
# untyped darwinConfigurations output as a unique option.
{
  libraryLib,
  mkUser,
  inputs,
  ...
}: let
  commonArgs = {
    inherit inputs;
    extraSpecialArgs = {inherit mkUser;};
  };
in {
  flake.darwinConfigurations = {
    wweaver = libraryLib.mkDarwinSystem (
      commonArgs
      // {
        hostname = "wweaver";
        modules = [
          ../archetypes/workstation-darwin.nix
          ../../modules/services/bifrost/darwin.nix
          (inputs.nix-darwin + "/modules/homebrew.nix")
          ../../modules/services/omlx/darwin.nix
          ../../modules/home-manager/aerospace.nix
          ../../hosts/wweaver
        ];
      }
    );

    darwin-server = libraryLib.mkDarwinSystem (
      commonArgs
      // {
        hostname = "darwin-server";
        modules = [
          ../archetypes/headless-server-darwin.nix
          {
            nixpkgs.config.permittedInsecurePackages = [
              "olm-3.2.16"
            ];
          }
          ../../hosts/darwin-server
        ];
      }
    );

    MegamanX = libraryLib.mkDarwinSystem (
      commonArgs
      // {
        hostname = "MegamanX";
        modules = [
          ../archetypes/workstation-darwin.nix
          (inputs.nix-darwin + "/modules/homebrew.nix")
          ../../modules/services/bifrost/darwin.nix
          ../../modules/services/searxng/darwin.nix
          ../../modules/services/caddy/darwin.nix
          ../../modules/services/omlx/darwin.nix
          ../../modules/services/prometheus/darwin.nix
          ../../modules/services/node-exporter/darwin.nix
          ../../modules/home-manager/aerospace.nix
          ../../hosts/megamanx
        ];
      }
    );
  };
}
