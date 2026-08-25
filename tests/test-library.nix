# Unit tests for library/lib/mk-system.nix
#
# Verifies mkDarwinSystem and mkNixosSystem produce the expected
# hostName, overlays, nixpkgs config, home-manager wiring, and
# override-priority behavior. A regression here affects every v2
# system built through the library helpers.
#
# Uses the real flake inputs (via `self.inputs`) and real archetype
# modules so these tests exercise the actual composition path rather
# than a hand-rolled stand-in. Evaluation only (`lib.evalModules`-style
# via nix-darwin/nixpkgs's own systemBuilders) — nothing is built.
{
  pkgs,
  self,
  ...
}: let
  inherit (pkgs) lib;
  inherit (self) inputs;
  libraryLib = import ../library/lib/mk-system.nix {inherit lib;};

  # ── mkDarwinSystem fixtures ────────────────────────────────────────────
  darwinResult = libraryLib.mkDarwinSystem {
    inherit inputs;
    hostname = "test-darwin-host";
    modules = [
      ../library/archetypes/base-darwin.nix
    ];
  };

  # ── mkNixosSystem fixtures ─────────────────────────────────────────────
  minimalNixosBoot = {
    boot.loader.grub.device = "nodev";
    fileSystems."/" = {
      device = "/dev/sda1";
      fsType = "ext4";
    };
    system.stateVersion = "25.05";
  };

  nixosResult = libraryLib.mkNixosSystem {
    inherit inputs;
    hostname = "test-nixos-host";
    system = "x86_64-linux";
    modules = [
      minimalNixosBoot
      {
        home-manager.users.testuser = _: {
          home.stateVersion = "25.05";
          home.username = "testuser";
          home.homeDirectory = "/home/testuser";
        };
        users.users.testuser.isNormalUser = true;
      }
    ];
  };

  # Second fixture with a normal-priority module definition plus an
  # `overrides` value, to verify override-priority (mkOverride 50) wins.
  nixosOverrideResult = libraryLib.mkNixosSystem {
    inherit inputs;
    hostname = "test-nixos-override-host";
    system = "x86_64-linux";
    modules = [
      (lib.recursiveUpdate minimalNixosBoot {
        myConfig.tailscale.enable = true;
      })
    ];
    overrides = {
      tailscale.enable = false;
    };
  };
in {
  mkDarwinSystemTest =
    pkgs.runCommand "test-mk-darwin-system"
    {}
    ''
      echo "=== Testing mkDarwinSystem ==="

      ${
        if darwinResult.config.networking.hostName == "test-darwin-host"
        then ''echo "  networking.hostName = test-darwin-host: OK"''
        else ''echo "  FAIL: networking.hostName should be test-darwin-host, got ${darwinResult.config.networking.hostName}"; exit 1''
      }

      ${
        if builtins.hasAttr "stable" darwinResult.pkgs
        then ''echo "  overlay 'stable' present: OK"''
        else ''echo "  FAIL: overlay 'stable' missing from pkgs"; exit 1''
      }

      ${
        if builtins.hasAttr "devenv" darwinResult.pkgs
        then ''echo "  overlay 'devenv' present: OK"''
        else ''echo "  FAIL: overlay 'devenv' missing from pkgs"; exit 1''
      }

      ${
        if builtins.hasAttr "zellij-pane-tracker" darwinResult.pkgs
        then ''echo "  overlay 'zellij-pane-tracker' present: OK"''
        else ''echo "  FAIL: overlay 'zellij-pane-tracker' missing from pkgs"; exit 1''
      }

      ${
        if darwinResult.config.nixpkgs.config.allowUnfree == true
        then ''echo "  nixpkgs.config.allowUnfree = true: OK"''
        else ''echo "  FAIL: nixpkgs.config.allowUnfree should be true"; exit 1''
      }

      echo "All mkDarwinSystem tests passed"
      touch $out
    '';

  mkNixosSystemTest =
    pkgs.runCommand "test-mk-nixos-system"
    {}
    ''
      echo "=== Testing mkNixosSystem ==="

      ${
        if nixosResult.config.networking.hostName == "test-nixos-host"
        then ''echo "  networking.hostName = test-nixos-host: OK"''
        else ''echo "  FAIL: networking.hostName should be test-nixos-host, got ${nixosResult.config.networking.hostName}"; exit 1''
      }

      ${
        if builtins.hasAttr "home-manager" nixosResult.config
        then ''echo "  home-manager.nixosModules.home-manager wired: OK"''
        else ''echo "  FAIL: home-manager option not present"; exit 1''
      }

      ${
        if builtins.hasAttr "onepassword-secrets" nixosResult.config.home-manager.users.testuser.programs
        then ''echo "  opnix.homeManagerModules.default in sharedModules: OK"''
        else ''echo "  FAIL: opnix.homeManagerModules.default missing from home-manager.sharedModules"; exit 1''
      }

      ${
        if nixosResult.config.nixpkgs.hostPlatform.system == "x86_64-linux"
        then ''echo "  nixpkgs.hostPlatform.system = x86_64-linux: OK"''
        else ''echo "  FAIL: nixpkgs.hostPlatform.system should be x86_64-linux, got ${nixosResult.config.nixpkgs.hostPlatform.system}"; exit 1''
      }

      ${
        if nixosResult.config.nixpkgs.config.allowUnfree == true
        then ''echo "  nixpkgs.config.allowUnfree = true: OK"''
        else ''echo "  FAIL: nixpkgs.config.allowUnfree should be true"; exit 1''
      }

      echo ""
      echo "=== Testing mkNixosSystem override priority (mkOverride 50) ==="

      ${
        if nixosOverrideResult.config.myConfig.tailscale.enable == false
        then ''echo "  overrides win over normal-priority module definition: OK"''
        else ''echo "  FAIL: overrides.tailscale.enable = false should win over myConfig.tailscale.enable = true"; exit 1''
      }

      echo "All mkNixosSystem tests passed"
      touch $out
    '';
}
