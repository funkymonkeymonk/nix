{pkgs, ...}: let
  runnerSource = builtins.readFile ./default.nix;
  usesPathInterpolation = pkgs.lib.hasInfix ''NIX_PATH = "nixpkgs=''${pkgs.path}"'' runnerSource;
  avoidsStringConversion = !(pkgs.lib.hasInfix ''NIX_PATH = "nixpkgs=''${toString pkgs.path}"'' runnerSource);
in {
  nixUnitRunner = pkgs.runCommand "test-nix-unit-runner" {} ''
    echo "=== Testing nix-unit runner Nixpkgs dependency ==="
    ${
      if usesPathInterpolation
      then ''echo "  NIX_PATH preserves the Nixpkgs store dependency: OK"''
      else ''echo "  FAIL: NIX_PATH must interpolate pkgs.path directly"; exit 1''
    }
    ${
      if avoidsStringConversion
      then ''echo "  NIX_PATH does not erase the store dependency with toString: OK"''
      else ''echo "  FAIL: NIX_PATH must not convert pkgs.path with toString"; exit 1''
    }
    touch $out
  '';
}
