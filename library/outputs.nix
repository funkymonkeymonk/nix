{inputs, ...}: {
  perSystem = {system, ...}: let
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [(import ../overlays {inherit inputs;})];
    };
    tests = import ../tests {
      inherit pkgs;
      self = inputs.self;
      inherit (inputs.nixpkgs) lib;
    };
    inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
  in {
    packages =
      {
        inherit (pkgs) rtk yaks lm-eval lighteval bfcl-eval bigcodebench evalscope openai-evals humaneval-mbpp;
        inherit (inputs.devenv.packages.${system}) devenv;
        installer = pkgs.callPackage ../packages/installer {};
      }
      // inputs.nixpkgs.lib.optionalAttrs isDarwin {
        inherit (pkgs) mlx-vlm mlx-audio mlx-embeddings gemma4-31B-4bit gemma4-e4B-4bit qwen3_8-27B-4bit qwen3_8-27B-mxfp4;
      }
      // inputs.nixpkgs.lib.optionalAttrs isLinux {
        iso = inputs.self.nixosConfigurations.installer-iso.config.system.build.isoImage;
      };

    apps.installer = {
      type = "app";
      program = "${pkgs.callPackage ../packages/installer {}}/bin/nixos-flake-installer";
    };

    checks =
      tests
      // inputs.nixpkgs.lib.optionalAttrs isDarwin {
        overlay-qwen38-mxfp4 = tests.overlay-qwen38-mxfp4;
      };
  };

  flake.lib.optionsDoc = import ../scripts/generate-options-doc.nix {
    lib = inputs.nixpkgs.lib;
    self = inputs.self;
  };
}
