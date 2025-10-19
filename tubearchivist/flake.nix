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
    # Use the standard helper to expose the flake on common systems.
    forAllSystems = flake-utils.lib.eachDefaultSystem;
  in
    forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        isX86Linux = system == "x86_64-linux";

        # Fetch the tubearchivist repository (main branch).
        # NOTE: you must replace the sha256 with the correct hash after the first build.
        src = pkgs.fetchFromGitHub {
          owner = "tubearchivist";
          repo = "tubearchivist";
          # upstream default branch is `develop`; build from `develop` so fetch works
          rev = "develop";
          sha256 = "05bfr65gx2j51h97vgs2y8k1ln1ypjyl1qpr69f1pzcnfnwqhcc4";
        };

        # On x86_64-linux build the real package using uv2nix; on other systems provide a tiny stub
        # so the flake can be inspected or queried without failing.
        realBuild =
          if isX86Linux
          then let
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
          in
            tubearchivistPkg
          else
            # Minimal stub that is cheap to build and clearly indicates unsupported platform.
            pkgs.runCommand "tubearchivist-not-supported" {} ''
              echo "tubearchivist is only built for x86_64-linux in this flake" > $out
            '';
      in {
        packages = {
          tubearchivist = realBuild;
        };

        # Make the package the default package for this flake/system.
        defaultPackage = self.packages.${system}.tubearchivist;
      }
    );
}
