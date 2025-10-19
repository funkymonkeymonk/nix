{
  description = "Flake to build tubearchivist (main) using uv2nix for x86_64-linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    uv2nix,
    pyproject-nix,
    pyproject-build-systems,
    flake-utils,
    ...
  }: let
    systems = ["x86_64-linux"];
    forSystems = flake-utils.lib.eachSystem systems;
  in
    forSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        # Fetch the tubearchivist repository (main branch).
        # NOTE: you must replace the sha256 with the correct hash after the first build.
        src = pkgs.fetchFromGitHub {
          owner = "tubearchivist";
          repo = "tubearchivist";
          rev = "main";
          sha256 = "0000000000000000000000000000000000000000000000000000";
        };

        # Load uv workspace from the fetched source.
        workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = src;};

        # Create a pyproject overlay for the workspace; prefer wheels where available.
        overlay = workspace.mkPyprojectOverlay {sourcePreference = "wheel";};

        # Build python set using pyproject.nix and the wheel overlay
        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages {
            python = pkgs.python3;
          }).overrideScope (lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            overlay
          ]);

        # Create a virtualenv package with the project's default deps.
        tubearchivistPkg = pythonSet.mkVirtualEnv "tubearchivist-env" workspace.deps.default;
      in {
        packages = {
          tubearchivist = tubearchivistPkg;
        };

        # Make the package the default package for this flake/system.
        defaultPackage = self.packages.${system}.tubearchivist;
      }
    );
}
