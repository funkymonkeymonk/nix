# Overlay package build/instantiation tests
#
# Verifies the custom packages defined in overlays/default.nix (backed by
# packages/<name>/default.nix) actually build and produce a working binary
# on PATH. Each package is fetched from an external source (crates.io via
# fetchFromGitHub, npm registry via fetchurl) and could silently break on
# a nixpkgs bump, a hash mismatch, or an upstream release removing the
# expected binary -- these tests catch that at eval/build time rather than
# at `darwin-rebuild switch` time on a real machine.
{pkgs, ...}: {
  # Test that rtk (Rust Token Killer CLI proxy) builds and its binary works
  rtkPackageTest =
    pkgs.runCommand "test-rtk-package"
    {
      nativeBuildInputs = [pkgs.rtk];
    }
    ''
      echo "=== Testing rtk package ==="

      if command -v rtk > /dev/null 2>&1; then
        echo "  rtk binary found: OK"
      else
        echo "  rtk binary NOT FOUND!"
        exit 1
      fi

      # --help should exit 0 and print usage without needing network access
      if rtk --help > /dev/null 2>&1; then
        echo "  rtk --help exits successfully: OK"
      else
        echo "  rtk --help failed!"
        exit 1
      fi

      echo "rtk package test passed"
      touch $out
    '';

  # Test that yaks (yx CLI, distributed TODO list) builds and its binary works
  yaksPackageTest =
    pkgs.runCommand "test-yaks-package"
    {
      nativeBuildInputs = [pkgs.yaks];
    }
    ''
      echo "=== Testing yaks package ==="

      if command -v yx > /dev/null 2>&1; then
        echo "  yx binary found: OK"
      else
        echo "  yx binary NOT FOUND!"
        exit 1
      fi

      if yx --help > /dev/null 2>&1; then
        echo "  yx --help exits successfully: OK"
      else
        echo "  yx --help failed!"
        exit 1
      fi

      echo "yaks package test passed"
      touch $out
    '';

  # Test that evalscope (ModelScope EvalScope LLM eval CLI) builds and its
  # binary works
  evalscopePackageTest =
    pkgs.runCommand "test-evalscope-package"
    {
      nativeBuildInputs = [pkgs.evalscope];
    }
    ''
      echo "=== Testing evalscope package ==="

      if command -v evalscope > /dev/null 2>&1; then
        echo "  evalscope binary found: OK"
      else
        echo "  evalscope binary NOT FOUND!"
        exit 1
      fi

      if evalscope --help > /dev/null 2>&1; then
        echo "  evalscope --help exits successfully: OK"
      else
        echo "  evalscope --help failed!"
        exit 1
      fi

      echo "evalscope package test passed"
      touch $out
    '';

  # Test that pi-coding-agent (pi CLI) builds and its binary works
  piCodingAgentPackageTest =
    pkgs.runCommand "test-pi-coding-agent-package"
    {
      nativeBuildInputs = [pkgs.pi-coding-agent];
    }
    ''
      echo "=== Testing pi-coding-agent package ==="

      if command -v pi > /dev/null 2>&1; then
        echo "  pi binary found: OK"
      else
        echo "  pi binary NOT FOUND!"
        exit 1
      fi

      if pi --help > /dev/null 2>&1; then
        echo "  pi --help exits successfully: OK"
      else
        echo "  pi --help failed!"
        exit 1
      fi

      echo "pi-coding-agent package test passed"
      touch $out
    '';

  # Test that bigcodebench (code generation/execution benchmark) builds and
  # its generate CLI entry point works
  bigcodebenchPackageTest =
    pkgs.runCommand "test-bigcodebench-package"
    {
      nativeBuildInputs = [pkgs.bigcodebench];
    }
    ''
      echo "=== Testing bigcodebench package ==="

      if command -v bigcodebench.generate > /dev/null 2>&1; then
        echo "  bigcodebench.generate binary found: OK"
      else
        echo "  bigcodebench.generate binary NOT FOUND!"
        exit 1
      fi

      if bigcodebench.generate --help > /dev/null 2>&1; then
        echo "  bigcodebench.generate --help exits successfully: OK"
      else
        echo "  bigcodebench.generate --help failed!"
        exit 1
      fi

      echo "bigcodebench package test passed"
      touch $out
    '';
}
