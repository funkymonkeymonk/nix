{inputs, ...}: {
  perSystem = {system, ...}: let
    pkgs = import inputs.nixpkgs {
      inherit system;
      config = import ./lib/nixpkgs-config-values.nix;
      overlays = [(import ../overlays {inherit inputs;})];
    };
    tests = import ../tests {
      inherit pkgs inputs;
      self = inputs.self;
      inherit (inputs.nixpkgs) lib;
    };
    inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
  in {
    packages =
      {
        inherit (pkgs) rtk yaks lm-eval lighteval bfcl-eval bigcodebench evalscope openai-evals humaneval-mbpp bifrost-ui bifrost-http;
        devenv = pkgs.devenv;
        installer = pkgs.callPackage ../packages/installer {};
        installer-ready = pkgs.callPackage ../packages/installer-ready {};
      }
      // inputs.nixpkgs.lib.optionalAttrs isDarwin {
        inherit (pkgs) mlx-vlm mlx-audio mlx-embeddings gemma4-31B-4bit gemma4-e4B-4bit qwen3_8-27B-4bit qwen3_8-27B-mxfp4;
      }
      // inputs.nixpkgs.lib.optionalAttrs isLinux {
        iso = inputs.self.nixosConfigurations.installer-iso.config.system.build.isoImage;
      }
      // inputs.nixpkgs.lib.optionalAttrs (
        system
        == "x86_64-linux"
        && builtins.getEnv "MACHINES_E2E_PUBLIC_KEY" != ""
        && builtins.getEnv "MACHINES_E2E_SSH_PORT" != ""
      ) {
        machines-e2e-vm =
          (inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              (inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
              ../tests/vm/machines-e2e-target.nix
            ];
          }).config.system.build.vm;
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
