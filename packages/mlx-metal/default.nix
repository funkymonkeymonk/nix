# mlx with Metal GPU support for Apple Silicon
# Pulls prebuilt wheels from PyPI and merges them, since building mlx with
# Metal in Nix requires Xcode toolchain sandbox escape.
# Based on: https://aldur.blog/micros/2025/11/04/mlx-with-metal-support-through-nix/
{
  lib,
  stdenv,
  fixDarwinDylibNames,
  python3Packages,
}: let
  inherit (python3Packages) buildPythonPackage fetchPypi python;

  version = "0.31.2";
  format = "wheel";
  platform = "macosx_15_0_arm64";
  pyVersion = lib.versions.majorMinor python.version;
  pythonTag = "cp${lib.replaceStrings ["."] [""] pyVersion}";

  mlx_metal = buildPythonPackage rec {
    inherit version format;
    pname = "mlx_metal";

    src = fetchPypi {
      inherit
        pname
        version
        format
        platform
        ;
      hash = "sha256-6dTl/ObKEKh6DjiFl/mVGa1ZTQnmdHCLUxK9i9T1mX0=";
      python = "py3";
      dist = "py3";
    };

    dontStrip = true;
    doCheck = false;
  };
in
  buildPythonPackage rec {
    inherit version format;
    pname = "mlx";

    src = fetchPypi {
      inherit
        pname
        version
        format
        platform
        ;
      hash = "sha256-NLAXHNnrXEP92CCR9hNdbMxaBlNjpKPmj6xk+05T03w=";
      python = pythonTag;
      dist = pythonTag;
      abi = pythonTag;
    };

    nativeBuildInputs = [
      fixDarwinDylibNames
    ];

    pythonRemoveDeps = [
      "mlx-metal"
    ];

    postInstall = ''
      metal_libdir=${mlx_metal}/lib/python${pyVersion}/site-packages/mlx
      cp -r "$metal_libdir/lib" "$out/lib/python${pyVersion}/site-packages/mlx/"
    '';

    postFixup = lib.optionalString stdenv.isDarwin ''
      libdir="$out/lib/python${pyVersion}/site-packages/mlx"

      if [ -f "$libdir/lib/libmlx.dylib" ]; then
        for so in "$libdir"/*.so; do
          if [ -f "$so" ] && [ "$so" != "$libdir/core.cpython-*-darwin.so" ]; then
            install_name_tool -add_rpath "$libdir/lib" "$so" 2>/dev/null || true
            install_name_tool -change @rpath/libmlx.dylib "$libdir/lib/libmlx.dylib" "$so" 2>/dev/null || true
          fi
        done
      else
        echo "ERROR: libmlx.dylib not found after copying from mlx_metal"
        exit 1
      fi
    '';

    dontStrip = true;
    doCheck = false;

    pythonImportsCheck = [
      "mlx.core"
    ];

    meta = {
      description = "MLX framework with Metal GPU support (prebuilt wheels)";
      homepage = "https://github.com/ml-explore/mlx";
      license = lib.licenses.mit;
      platforms = lib.platforms.darwin;
      broken = !stdenv.isDarwin || !stdenv.isAarch64;
    };
  }
